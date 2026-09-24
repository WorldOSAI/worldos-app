import UIKit
import Capacitor
import WebKit
import AppTrackingTransparency

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

    override func load() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.onActive()
        }
    }

    deinit {
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

    // Called after the WebView is presented and whenever Settings returns focus.
    // No prompt here: the Web raises the system prompt itself (requestAuthorization),
    // after its own explainer and only once the visitor is signed in — asking cold on
    // the first screen was the lowest-yield moment, and Apple only lets us ask once.
    func onActive() {
        guard webViewPresented, UIApplication.shared.applicationState == .active else { return }
        notifyListeners("statusChanged", data: statusPayload())
    }

    @objc func getStatus(_ call: CAPPluginCall) {
        DispatchQueue.main.async { call.resolve(self.statusPayload()) }
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
            self.requestIfNeeded()
        }
    }

    private func requestIfNeeded() {
        guard !requesting, ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        requesting = true
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requesting = false
                let payload = self.statusPayload()
                let calls = self.pendingCalls
                self.pendingCalls.removeAll()
                calls.forEach { $0.resolve(payload) }
                self.notifyListeners("statusChanged", data: payload)
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
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}
