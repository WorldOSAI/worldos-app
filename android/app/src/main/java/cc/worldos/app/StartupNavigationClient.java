package cc.worldos.app;

import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeWebViewClient;

/** Keeps a transient first-load failure behind the launch skeleton while recovering. */
final class StartupNavigationClient extends BridgeWebViewClient {
    private static final String TAG = "WorldOSNavigation";
    private final Bridge bridge;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final StartupRetryPolicy retryPolicy;
    private boolean retryPending;
    private boolean destroyed;

    StartupNavigationClient(Bridge bridge) {
        super(bridge);
        this.bridge = bridge;
        retryPolicy = new StartupRetryPolicy(bridge.getServerUrl(), SystemClock.uptimeMillis());
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
        retryPolicy.onPageStarted(url);
        super.onPageStarted(view, url, favicon);
    }

    @Override
    public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
        String url = request.getUrl().toString();
        // A failed navigation can emit additional callbacks before the retry.
        // They must not consume the budget or replace the pending load with offline.html.
        if (retryPending && request.isForMainFrame() && retryPolicy.isServiceUrl(url)) return;
        long delay = retryPolicy.retryDelay(url, request.isForMainFrame(), error.getErrorCode(), SystemClock.uptimeMillis());
        if (!destroyed && delay >= 0) {
            Log.w(TAG, "Startup connection failed code=" + error.getErrorCode()
                + "; automatic retry=" + retryPolicy.attempts());
            retryPending = true;
            // On cold start WebView can navigate before Android's VPN HTTP proxy
            // reaches its network context. Yield to proxy initialization, then
            // retry the exact URL, preserving deep links and query parameters.
            handler.postDelayed(() -> {
                retryPending = false;
                if (destroyed) return;
                if (retryPolicy.canRunRetry(SystemClock.uptimeMillis())) {
                    view.loadUrl(url);
                } else {
                    retryPolicy.finish();
                    String errorUrl = bridge.getErrorUrl();
                    if (errorUrl != null) view.loadUrl(errorUrl);
                }
            }, delay);
            return;
        }
        if (request.isForMainFrame() && retryPolicy.isServiceUrl(url)) {
            retryPolicy.finish();
            Log.w(TAG, "Main frame failed code=" + error.getErrorCode() + "; showing fallback");
        }
        super.onReceivedError(view, request, error);
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
        // WebView also commits its internal error document under the failed
        // remote URL. Do not expose it or mark startup successful while retrying.
        if (retryPolicy.shouldIgnoreCommit(url, retryPending)) return;
        if (retryPolicy.onPageCommitted(url, retryPending)) {
            Log.i(TAG, "Startup ready; automatic retries=" + retryPolicy.attempts());
        }
        super.onPageCommitVisible(view, url);
    }

    @Override
    public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
        if (request.isForMainFrame() && retryPolicy.isServiceUrl(request.getUrl().toString())) {
            handler.removeCallbacksAndMessages(null);
            retryPending = false;
            retryPolicy.finish();
            Log.w(TAG, "Main frame HTTP failure status=" + response.getStatusCode());
        }
        super.onReceivedHttpError(view, request, response);
    }

    void destroy() {
        destroyed = true;
        retryPending = false;
        retryPolicy.finish();
        handler.removeCallbacksAndMessages(null);
    }
}
