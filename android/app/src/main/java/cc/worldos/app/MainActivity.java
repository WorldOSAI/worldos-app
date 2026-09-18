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
    }
}
