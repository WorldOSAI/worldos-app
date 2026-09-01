package cc.worldos.app;

import android.os.Build;
import android.os.Bundle;
import android.view.View;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Android 16 enforces edge-to-edge and ignores StatusBar.overlaysWebView.
        // Keep the WebView itself inside the physical system-bar safe area so
        // every route is protected, including routes without a Web header.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            View webView = getBridge().getWebView();
            ViewCompat.setOnApplyWindowInsetsListener(webView, (view, windowInsets) -> {
                Insets systemBars = windowInsets.getInsets(
                    WindowInsetsCompat.Type.statusBars() | WindowInsetsCompat.Type.navigationBars()
                );
                view.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom);
                return windowInsets;
            });
            ViewCompat.requestApplyInsets(webView);
        }
    }
}
