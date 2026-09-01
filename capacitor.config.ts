import type { CapacitorConfig } from "@capacitor/cli";
import { KeyboardResize } from "@capacitor/keyboard";

const serverUrl = process.env.CAPACITOR_SERVER_URL?.trim() || "https://worldos.cc";
const isReleaseBuild = process.env.CAPACITOR_BUILD_MODE === "release";

if (isReleaseBuild && serverUrl !== "https://worldos.cc") {
  throw new Error(
    `Release builds must use https://worldos.cc, received ${serverUrl}`,
  );
}

const serverHostname = new URL(serverUrl).hostname;

const config: CapacitorConfig = {
  appId: "cc.worldos.app",
  appName: "WorldOS",
  webDir: "mobile-dist",
  server: {
    url: serverUrl,
    cleartext: serverUrl.startsWith("http://"),
    errorPath: "offline.html",
    // The bundled offline page starts on capacitor://localhost. Keep recovery
    // navigation to this build's configured host inside the WebView.
    allowNavigation: [...new Set([serverHostname, "worldos.cc", "*.worldos.cc"])],
  },
  plugins: {
    StatusBar: {
      // The native shell owns the physical status-bar inset. Web pages may or
      // may not render their own header, so the WebView must never rely on a
      // page-level header to stay clear of the system status bar.
      overlaysWebView: false,
      backgroundColor: "#ffffff",
      style: "DEFAULT",
    },
    SplashScreen: {
      // Keep the native launch screen over the WebView until the first React
      // frame is ready. The runtime hides it earlier; this is the fail-safe so
      // an unreachable server reveals offline.html instead of hanging forever.
      launchShowDuration: 6_000,
      launchAutoHide: true,
      backgroundColor: "#ffffff",
      androidScaleType: "CENTER",
      showSpinner: false,
    },
    Keyboard: {
      resize: KeyboardResize.Native,
      resizeOnFullScreen: true,
    },
    PushNotifications: {
      presentationOptions: ["badge", "sound", "alert"],
    },
    SocialLogin: {
      providers: {
        google: true,
        facebook: false,
        apple: true,
        twitter: false,
      },
      logLevel: process.env.NODE_ENV === "production" ? 1 : 2,
    },
  },
};

export default config;
