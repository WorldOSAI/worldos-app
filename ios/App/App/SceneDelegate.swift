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

class WorldOSBridgeViewController: CAPBridgeViewController {
    private let trackingAuthorization = TrackingAuthorizationPlugin()

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginType(NavigationGesturePlugin.self)
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
