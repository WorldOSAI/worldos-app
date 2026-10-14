package cc.worldos.app;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.UUID;

@CapacitorPlugin(name = "AppReviewContext")
public class AppReviewContextPlugin extends Plugin {
    private static final String SESSION_ID = UUID.randomUUID().toString();

    @PluginMethod
    public void getContext(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            try {
                // APK-only devices without Play cannot use the Play review flow.
                getContext().getPackageManager().getPackageInfo("com.android.vending", 0);
                SharedPreferences prefs = getContext().getSharedPreferences("worldos_review", Context.MODE_PRIVATE);
                String installationId = prefs.getString("installation", null);
                if (installationId == null) {
                    installationId = UUID.randomUUID().toString();
                    if (!prefs.edit().putString("installation", installationId).commit()) {
                        call.reject("Review context unavailable");
                        return;
                    }
                }
                JSObject result = new JSObject();
                result.put("installationId", installationId);
                result.put("sessionId", SESSION_ID);
                result.put("active", getActivity().hasWindowFocus());
                result.put("appVersion", getContext().getPackageManager().getPackageInfo(getContext().getPackageName(), 0).versionName);
                result.put("osVersion", Build.VERSION.RELEASE);
                call.resolve(result);
            } catch (Exception error) {
                call.reject("Review context unavailable", error);
            }
        });
    }
}
