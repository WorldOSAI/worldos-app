import UIKit
import Capacitor
import WebKit
import AppTrackingTransparency
import Security
import OSLog
import Photos
import UniformTypeIdentifiers

@objc(TrackingAuthorizationPlugin)
class TrackingAuthorizationPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "TrackingAuthorizationPlugin"
    let jsName = "TrackingAuthorization"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuthorization", returnType: CAPPluginReturnPromise)
    ]

    private var activationObserver: NSObjectProtocol?
    private var webViewPresented = false
    private var requesting = false
    private var pendingCalls: [CAPPluginCall] = []
    private var startupPrompt: DispatchWorkItem?
    private var startupAttempts = 0
    private let trackingLog = Logger(subsystem: "cc.worldos.app", category: "TrackingAuthorization")

    override func load() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.onActive()
        }
    }

    deinit {
        startupPrompt?.cancel()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    private func statusPayload() -> [String: Any] {
        let status: String
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized: status = "authorized"
        case .denied: status = "denied"
        case .restricted: status = "restricted"
        case .notDetermined: status = "notDetermined"
        @unknown default: status = "unknown"
        }
        return ["status": status, "canTrack": status == "authorized"]
    }

    func onWebViewPresented() {
        webViewPresented = true
        onActive()
    }

    // The native installation owns ATT startup. Do not require remote-page
    // hydration, account state or third-party SDK setup to ask the system.
    // The existing Web method shares this request and remains compatible.
    func onActive() {
        guard webViewPresented, UIApplication.shared.applicationState == .active else { return }
        notifyListeners("statusChanged", data: statusPayload())
        scheduleStartupPrompt()
    }

    private func scheduleStartupPrompt() {
        guard startupPrompt == nil, startupAttempts < 3, !requesting,
              webViewPresented, UIApplication.shared.applicationState == .active,
              ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startupPrompt = nil
            guard UIApplication.shared.applicationState == .active else { return }
            // Wait out native sign-in/permission presentations. Web overlays do
            // not own or gate this installation-level system permission.
            guard self.bridge?.viewController?.presentedViewController == nil else {
                self.scheduleStartupPrompt()
                return
            }
            guard !self.requesting,
                  ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
            self.startupAttempts += 1
            self.requestIfNeeded(source: "startup")
        }
        startupPrompt = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.trackingLog.info("ATT Web status lookup: \(ATTrackingManager.trackingAuthorizationStatus.rawValue, privacy: .public)")
            call.resolve(self.statusPayload())
        }
    }

    @objc func requestAuthorization(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.requesting {
                self.pendingCalls.append(call)
                return
            }
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
                call.resolve(self.statusPayload())
                return
            }
            guard UIApplication.shared.applicationState == .active else {
                call.reject("ATT requires the app to be active", "APP_NOT_ACTIVE")
                return
            }
            self.pendingCalls.append(call)
            self.requestIfNeeded(source: "web")
        }
    }

    private func requestIfNeeded(source: String) {
        guard !requesting, ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        startupPrompt?.cancel()
        startupPrompt = nil
        requesting = true
        trackingLog.info("ATT requesting authorization from \(source, privacy: .public)")
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requesting = false
                let payload = self.statusPayload()
                let calls = self.pendingCalls
                self.pendingCalls.removeAll()
                calls.forEach { $0.resolve(payload) }
                self.notifyListeners("statusChanged", data: payload)
                self.trackingLog.info("ATT authorization result: \(ATTrackingManager.trackingAuthorizationStatus.rawValue, privacy: .public)")
                self.scheduleStartupPrompt()
            }
        }
    }
}

@objc(NavigationGesturePlugin)
class NavigationGesturePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "NavigationGesturePlugin"
    let jsName = "NavigationGesture"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setEnabled", returnType: CAPPluginReturnPromise)
    ]

    @objc func setEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.webView?.allowsBackForwardNavigationGestures = enabled
            call.resolve()
        }
    }
}

/// Capacitor loads `server.errorPath` (offline.html) on EVERY failed provisional navigation,
/// including NSURLErrorCancelled (-999): a full-page load superseded by the next one, e.g. a
/// link tapped while a redirect was still in flight. That is not "offline" — the WebView is
/// already loading the newer page — so that one error is dropped here. Everything else the
/// delegate does is forwarded to Capacitor's own handler untouched.
final class CancelledNavigationFilter: NSObject, WKNavigationDelegate {
    private weak var target: (NSObject & WKNavigationDelegate)?

    init(forwardingTo target: NSObject & WKNavigationDelegate) {
        self.target = target
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (target?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        target
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled {
            CAPLog.print("⚡️  WebView navigation cancelled by a newer one (-999); not offline")
            return
        }
        target?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    // The same cancellation can hit a page that has already COMMITTED but is still streaming
    // its document (Next.js streams HTML): a newer navigation stops that loader with -999 and
    // Capacitor's committed-load handler would load offline.html — cancelling the healthy
    // newer navigation in the process.
    // swiftlint:disable:next implicitly_unwrapped_optional
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled {
            CAPLog.print("⚡️  WebView committed load cancelled by a newer navigation (-999); not offline")
            return
        }
        target?.webView?(webView, didFail: navigation, withError: error)
    }
}

/// Saves a file the page made (map timelapse video, share poster) to Photos. The WebView
/// ignores `<a download>` on a blob: URL, so without this the page's Download button does
/// nothing. Same contract as the Android MediaSavePlugin: the page streams the bytes in base64
/// chunks (begin → append… → finish) into a temp file, then finish adds it to Photos with
/// add-only access (NSPhotoLibraryAddUsageDescription). One file at a time: a new begin discards
/// an unfinished one, and every later call names its session, so a superseded save can't touch
/// the new one. A denied Photos permission rejects with code PERMISSION_DENIED.
@objc(MediaSavePlugin)
class MediaSavePlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "MediaSavePlugin"
    let jsName = "MediaSave"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "begin", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "append", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "finish", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise)
    ]

    /// the 48s 1080p video is ~27 MB; anything far past that is not ours
    private static let maxBytes = 200 * 1024 * 1024
    /// Photos takes these; webm is not one of them, so it is refused up front
    private static let mimeTypes: Set<String> = ["video/mp4", "image/png", "image/jpeg", "image/webp"]

    /// every session field is touched only on this queue
    private let queue = DispatchQueue(label: "cc.worldos.app.media-save")
    private var sessionId: String?
    private var pendingFile: URL?
    private var pendingMime: String?
    private var written = 0

    @objc func begin(_ call: CAPPluginCall) {
        // a codecs parameter ("video/mp4;codecs=avc1") is not part of the file's type
        let mime = (call.getString("mimeType") ?? "").split(separator: ";").first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard Self.mimeTypes.contains(mime) else {
            call.reject("Unsupported media type")
            return
        }
        let fileName = Self.safeName(call.getString("fileName") ?? "")
        queue.async {
            self.discard()
            do {
                // each save gets its own folder under tmp; folders a killed or abandoned save
                // left behind are swept here (an in-flight Photos import is minutes younger)
                let id = UUID().uuidString
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("media-save", isDirectory: true)
                Self.purgeStale(root)
                let dir = root.appendingPathComponent(id, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let file = dir.appendingPathComponent(fileName)
                guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                self.sessionId = id
                self.pendingFile = file
                self.pendingMime = mime
                self.written = 0
                call.resolve(["id": id])
            } catch {
                self.discard()
                call.reject("Media save unavailable", nil, error)
            }
        }
    }

    @objc func append(_ call: CAPPluginCall) {
        queue.async {
            guard let file = self.currentFile(call) else { return }
            do {
                guard let bytes = Data(base64Encoded: call.getString("data") ?? "") else {
                    throw CocoaError(.coderInvalidValue)
                }
                guard self.written + bytes.count <= Self.maxBytes else { throw CocoaError(.fileWriteOutOfSpace) }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: bytes)
                self.written += bytes.count
                call.resolve()
            } catch {
                self.discard()
                call.reject("Media save failed", nil, error)
            }
        }
    }

    @objc func finish(_ call: CAPPluginCall) {
        queue.async {
            guard let file = self.currentFile(call), let mime = self.pendingMime else { return }
            let empty = self.written == 0
            self.reset()
            if empty {
                Self.deleteSave(file)
                call.reject("Media save failed")
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                // add-only access is either authorized or not (.limited is a read-write state)
                guard status == .authorized else {
                    Self.deleteSave(file)
                    call.reject("Photos access denied", "PERMISSION_DENIED")
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = file.lastPathComponent
                    options.uniformTypeIdentifier = UTType(mimeType: mime)?.identifier
                    PHAssetCreationRequest.forAsset().addResource(
                        with: mime.hasPrefix("video/") ? .video : .photo, fileURL: file, options: options)
                }) { saved, error in
                    Self.deleteSave(file)
                    if saved {
                        call.resolve(["savedTo": "gallery"])
                    } else {
                        call.reject("Media save failed", nil, error)
                    }
                }
            }
        }
    }

    /// drops the named save's partial file; a superseded or finished save is left alone
    @objc func cancel(_ call: CAPPluginCall) {
        queue.async {
            if let id = self.sessionId, id == call.getString("id") { self.discard() }
            call.resolve()
        }
    }

    /// the pending file when `call` names the current save; rejects a superseded one
    private func currentFile(_ call: CAPPluginCall) -> URL? {
        if let id = sessionId, id == call.getString("id"), let file = pendingFile { return file }
        call.reject("No media save in progress")
        return nil
    }

    private func discard() {
        if let file = pendingFile { Self.deleteSave(file) }
        reset()
    }

    private func reset() {
        sessionId = nil
        pendingFile = nil
        pendingMime = nil
        written = 0
    }

    /// removes save folders older than ten minutes
    private static func purgeStale(_ root: URL) {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (modified ?? .distantPast) < cutoff { try? FileManager.default.removeItem(at: entry) }
        }
    }

    /// removes a save's file and its folder
    private static func deleteSave(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// the page's file name with only what a file system rejects replaced; letters in any script
    /// stay. Kept under 200 bytes of UTF-8 by trimming whole characters off the base name, never
    /// the extension; an empty or hidden name gets a prefix.
    private static func safeName(_ name: String) -> String {
        let banned = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        var clean = String(String.UnicodeScalarView(name.unicodeScalars.map { banned.contains($0) ? "_" : $0 }))
            .trimmingCharacters(in: .whitespaces)
        var ext = ""
        if let dot = clean.lastIndex(of: "."), dot > clean.startIndex, clean.distance(from: dot, to: clean.endIndex) <= 10 {
            ext = String(clean[dot...])
            clean = String(clean[..<dot])
        }
        let budget = 200 - ext.utf8.count
        var base = ""
        for character in clean {
            if base.utf8.count + String(character).utf8.count > budget { break }
            base.append(character)
        }
        let out = base + ext
        return out.isEmpty || out.hasPrefix(".") ? "worldos" + out : out
    }
}

class WorldOSBridgeViewController: CAPBridgeViewController {
    private let trackingAuthorization = TrackingAuthorizationPlugin()
    // navigationDelegate is weak: keep the filter alive for the WebView's lifetime
    private var navigationFilter: CancelledNavigationFilter?

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        // Capacitor 8 bridges auto-register package plugins by default. In that
        // mode registerPluginType(_:) intentionally returns without doing anything,
        // so an app-local plugin must be registered as an instance instead.
        bridge?.registerPluginInstance(NavigationGesturePlugin())
        bridge?.registerPluginInstance(AppReviewContextPlugin())
        bridge?.registerPluginInstance(DeviceIdentityPlugin())
        bridge?.registerPluginInstance(trackingAuthorization)
        bridge?.registerPluginInstance(MediaSavePlugin())
        webView?.allowsBackForwardNavigationGestures = false
        if let webView, let handler = webView.navigationDelegate as? (NSObject & WKNavigationDelegate) {
            let filter = CancelledNavigationFilter(forwardingTo: handler)
            navigationFilter = filter
            webView.navigationDelegate = filter
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        trackingAuthorization.onWebViewPresented()
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = WorldOSBridgeViewController()
        // Register Capacitor's cold-start replay before presenting the controller.
        // The proxy waits for plugin registration before forwarding launch URLs to
        // App.getLaunchUrl/appUrlOpen and the AppsFlyer attribution cache.
        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
        window?.makeKeyAndVisible()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}

// Process identity survives WebView reloads and foreground transitions. The installation
// ID is random and scoped to this app; it is not an advertising/device identifier.
@objc(AppReviewContextPlugin)
class AppReviewContextPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "AppReviewContextPlugin"
    let jsName = "AppReviewContext"
    let pluginMethods: [CAPPluginMethod] = [CAPPluginMethod(name: "getContext", returnType: CAPPluginReturnPromise)]
    private static let sessionId = UUID().uuidString

    @objc func getContext(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            let key = "worldos.review.installation"
            let installationId = defaults.string(forKey: key) ?? UUID().uuidString
            defaults.set(installationId, forKey: key)
            call.resolve([
                "installationId": installationId,
                "sessionId": Self.sessionId,
                "active": UIApplication.shared.applicationState == .active,
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "osVersion": UIDevice.current.systemVersion
            ])
        }
    }
}

// A device id that survives uninstall/reinstall, for fraud prevention only (WorldSims caps the
// accounts one phone may create — lib/deviceLimit.server.ts). A random UUID kept in the Keychain,
// which iOS keeps when the app is deleted; ThisDeviceOnly so a backup restored onto another phone
// does not carry it over. Not the IDFA, never used for ads.
@objc(DeviceIdentityPlugin)
class DeviceIdentityPlugin: CAPPlugin, CAPBridgedPlugin {
    let identifier = "DeviceIdentityPlugin"
    let jsName = "DeviceIdentity"
    let pluginMethods: [CAPPluginMethod] = [CAPPluginMethod(name: "getId", returnType: CAPPluginReturnPromise)]
    private static let service = "cc.worldos.app.device-identity"
    private static let account = "device-id"

    @objc func getId(_ call: CAPPluginCall) {
        if let id = Self.read() ?? Self.create() {
            call.resolve(["id": "i_" + id])
        } else {
            call.reject("Device identity unavailable")
        }
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let id = String(data: data, encoding: .utf8), !id.isEmpty else { return nil }
        return id
    }

    private static func create() -> String? {
        let id = UUID().uuidString.lowercased()
        var query = baseQuery()
        query[kSecValueData as String] = Data(id.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        // a concurrent first call may have added it a moment ago: use whichever is stored
        if status == errSecDuplicateItem { return read() }
        return status == errSecSuccess ? id : nil
    }
}
