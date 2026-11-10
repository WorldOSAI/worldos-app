package cc.worldos.app;

import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.WebView;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.getcapacitor.BridgeActivity;
import com.getcapacitor.CapConfig;
import com.getcapacitor.Logger;
import com.getcapacitor.WebViewListener;

public class MainActivity extends BridgeActivity {
    /** Fail-safe: the skeleton never outlives this, whatever the network does. */
    private static final long LAUNCH_SKELETON_TIMEOUT_MS = 8_000;
    private static final long LAUNCH_SKELETON_FADE_MS = 150;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Runnable launchSkeletonTimeout = () -> hideLaunchSkeleton(LAUNCH_SKELETON_FADE_MS);
    private View launchSkeleton;
    private ObjectAnimator launchSkeletonPulse;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        registerPlugin(AppReviewContextPlugin.class);
        registerPlugin(DeviceIdentityPlugin.class);
        registerPlugin(MediaSavePlugin.class);
        boolean coldLaunch = savedInstanceState == null;
        if (coldLaunch) disableLaunchSplashHold();
        super.onCreate(savedInstanceState);

        // Android 15+ enforces edge-to-edge for apps targeting API 35 or later.
        // Apply the insets to the WebView's container, not the WebView: the
        // container receives them first, before they can be passed to the page.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            View webViewContainer = (View) getBridge().getWebView().getParent();
            ViewCompat.setOnApplyWindowInsetsListener(webViewContainer, (view, windowInsets) -> {
                Insets systemBars = windowInsets.getInsets(
                    WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout()
                );
                Insets ime = windowInsets.getInsets(WindowInsetsCompat.Type.ime());
                boolean keyboardVisible = windowInsets.isVisible(WindowInsetsCompat.Type.ime());
                view.setPadding(
                    systemBars.left,
                    systemBars.top,
                    systemBars.right,
                    keyboardVisible ? ime.bottom : systemBars.bottom
                );

                // Avoid applying the same safe-area inset again inside WebView.
                return new WindowInsetsCompat.Builder(windowInsets)
                    .setInsets(
                        WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout(),
                        Insets.of(0, 0, 0, 0)
                    )
                    .build();
            });
            ViewCompat.requestApplyInsets(webViewContainer);
        }

        if (coldLaunch) showLaunchSkeleton();
    }

    @Override
    public void onDestroy() {
        mainHandler.removeCallbacks(launchSkeletonTimeout);
        if (launchSkeletonPulse != null) launchSkeletonPulse.cancel();
        super.onDestroy();
    }

    /**
     * The splash plugin's launch screen holds the activity's FIRST FRAME (setKeepOnScreenCondition)
     * until the remote page hides it — up to launchShowDuration (6s). Play counts that whole wait
     * as cold start, and a tap during it has no focused window to go to (ANR). Android only: the
     * shared capacitor.config.ts keeps 6s for iOS, so the override is made here, on this launch's
     * config, before the bridge reads it. The native skeleton below takes the splash's place.
     */
    private void disableLaunchSplashHold() {
        try {
            CapConfig launchConfig = CapConfig.loadDefault(this);
            launchConfig.getPluginConfiguration("SplashScreen").getConfigJSON().put("launchShowDuration", 0);
            config = launchConfig;
        } catch (Exception e) {
            Logger.warn("Launch splash override failed; keeping the configured splash: " + e.getMessage());
        }
    }

    /** Native skeleton over the WebView, drawn on the first frame; removed once the page paints. */
    private void showLaunchSkeleton() {
        if (getBridge() == null) return;
        WebView webView = getBridge().getWebView();
        if (webView == null || !(webView.getParent() instanceof ViewGroup)) return;
        ViewGroup container = (ViewGroup) webView.getParent();
        launchSkeleton = getLayoutInflater().inflate(R.layout.launch_skeleton, container, false);
        container.addView(launchSkeleton);

        launchSkeletonPulse = ObjectAnimator.ofFloat(launchSkeleton.findViewById(R.id.launch_skeleton_content), View.ALPHA, 1f, 0.55f);
        launchSkeletonPulse.setDuration(900);
        launchSkeletonPulse.setRepeatMode(ValueAnimator.REVERSE);
        launchSkeletonPulse.setRepeatCount(ValueAnimator.INFINITE);
        launchSkeletonPulse.start();

        // WebViewClient callbacks run on the main thread; hideLaunchSkeleton is idempotent.
        getBridge().addWebViewListener(new WebViewListener() {
            @Override
            public void onPageCommitVisible(WebView view, String url) {
                hideLaunchSkeleton(LAUNCH_SKELETON_FADE_MS);
            }

            @Override
            public void onReceivedError(WebView view) {
                // the bridge loads offline.html next — let it show
                hideLaunchSkeleton(0);
            }
        });
        mainHandler.postDelayed(launchSkeletonTimeout, LAUNCH_SKELETON_TIMEOUT_MS);
    }

    private void hideLaunchSkeleton(long fadeMs) {
        View skeleton = launchSkeleton;
        if (skeleton == null) return;
        launchSkeleton = null;
        mainHandler.removeCallbacks(launchSkeletonTimeout);
        if (launchSkeletonPulse != null) {
            launchSkeletonPulse.cancel();
            launchSkeletonPulse = null;
        }
        Runnable remove = () -> {
            if (skeleton.getParent() instanceof ViewGroup) ((ViewGroup) skeleton.getParent()).removeView(skeleton);
        };
        if (fadeMs <= 0) {
            remove.run();
        } else {
            skeleton.animate().alpha(0f).setDuration(fadeMs).withEndAction(remove).start();
        }
    }
}
