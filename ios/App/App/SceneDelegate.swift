import UIKit
import Capacitor
import WebKit
import AppTrackingTransparency
import Security
import OSLog

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

class WorldOSBridgeViewController: CAPBridgeViewController {
    private let trackingAuthorization = TrackingAuthorizationPlugin()
    // navigationDelegate is weak: keep the filter alive for the WebView's lifetime
    private var navigationFilter: CancelledNavigationFilter?

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        // The fallback pages must retry the configured remote service, not
        // Capacitor.getServerUrl(), which returns the local asset origin.
        if let serverURL = bridge?.config.appStartServerURL,
           let encoded = try? JSONEncoder().encode(serverURL.absoluteString),
           let literal = String(data: encoded, encoding: .utf8) {
            webView?.configuration.userContentController.addUserScript(WKUserScript(
                source: "window.WorldOSAppServerURL = \(literal);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        // Capacitor 8 bridges auto-register package plugins by default. In that
        // mode registerPluginType(_:) intentionally returns without doing anything,
        // so an app-local plugin must be registered as an instance instead.
        bridge?.registerPluginInstance(NavigationGesturePlugin())
        bridge?.registerPluginInstance(AppReviewContextPlugin())
        bridge?.registerPluginInstance(DeviceIdentityPlugin())
        bridge?.registerPluginInstance(trackingAuthorization)
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
