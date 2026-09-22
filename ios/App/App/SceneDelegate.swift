import UIKit
import Capacitor
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
    private var launchRequestAttempted = false
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
    func onActive() {
        guard webViewPresented, UIApplication.shared.applicationState == .active else { return }
        notifyListeners("statusChanged", data: statusPayload())
        guard !launchRequestAttempted else { return }
        launchRequestAttempted = true
        requestIfNeeded()
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
            self.launchRequestAttempted = true
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
class NavigationGesturePlugin: CAPPlugin, CAPBridgedPlugin, UIGestureRecognizerDelegate {
    let identifier = "NavigationGesturePlugin"
    let jsName = "NavigationGesture"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setEnabled", returnType: CAPPluginReturnPromise)
    ]

    private var sheetPan: UIScreenEdgePanGestureRecognizer?
    private var sheetGestureActive = false
    private var inactiveObserver: NSObjectProtocol?

    override func load() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let webView = self.bridge?.webView else { return }
            let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(self.handleSheetPan(_:)))
            pan.edges = .left
            pan.delegate = self
            pan.isEnabled = false
            webView.addGestureRecognizer(pan)
            // An edge dismissal wins over the WebView's ordinary scrolling gesture.
            webView.scrollView.panGestureRecognizer.require(toFail: pan)
            self.sheetPan = pan
            self.inactiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let pan = self?.sheetPan else { return }
                let enabled = pan.isEnabled
                pan.isEnabled = false // sends cancelled if the finger was still down
                pan.isEnabled = enabled
            }
        }
    }

    deinit {
        if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
    }

    // Additive option: existing Web clients keep their normal page-navigation behavior.
    // New clients pass enabled:false, sheet:true so older Apps safely disable the page
    // snapshot animation instead of accidentally navigating underneath a sheet.
    @objc func setEnabled(_ call: CAPPluginCall) {
        let enabled = call.getBool("enabled") ?? false
        let sheet = call.getBool("sheet") ?? false
        DispatchQueue.main.async { [weak self] in
            guard let self, let webView = self.bridge?.webView else {
                call.reject("Navigation WebView is unavailable", "WEBVIEW_UNAVAILABLE")
                return
            }
            webView.allowsBackForwardNavigationGestures = enabled && !sheet
            self.sheetPan?.isEnabled = sheet
            call.resolve()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIScreenEdgePanGestureRecognizer,
              let view = pan.view else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
    }

    @objc private func handleSheetPan(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard let view = pan.view else { return }
        let phase: String
        switch pan.state {
        case .began:
            sheetGestureActive = true
            phase = "began"
        case .changed:
            guard sheetGestureActive else { return }
            phase = "changed"
        case .ended, .cancelled, .failed:
            guard sheetGestureActive else { return }
            sheetGestureActive = false
            phase = pan.state == .ended ? "ended" : "cancelled"
        default: return
        }
        let width = max(1, view.bounds.width)
        notifyListeners("sheetGesture", data: [
            "phase": phase,
            "progress": min(1, max(0, pan.translation(in: view).x / width)),
            "velocity": pan.velocity(in: view).x / width
        ])
        // JS owns animation completion and sheet-close navigation; never goBack here.
    }
}

class WorldOSBridgeViewController: CAPBridgeViewController {
    private let trackingAuthorization = TrackingAuthorizationPlugin()

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        // Capacitor 8 bridges auto-register package plugins by default. In that
        // mode registerPluginType(_:) intentionally returns without doing anything,
        // so an app-local plugin must be registered as an instance instead.
        bridge?.registerPluginInstance(NavigationGesturePlugin())
        bridge?.registerPluginInstance(trackingAuthorization)
        webView?.allowsBackForwardNavigationGestures = false
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
