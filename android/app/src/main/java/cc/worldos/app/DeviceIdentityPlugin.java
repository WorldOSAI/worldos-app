package cc.worldos.app;

import android.annotation.SuppressLint;
import android.provider.Settings;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/**
 * A device id that survives uninstall/reinstall, for fraud prevention only (WorldSims caps the
 * accounts one phone may create — lib/deviceLimit.server.ts). ANDROID_ID is scoped to this app's
 * signing key on Android 8+, unchanged by a reinstall and reset by a factory reset. Only a salted
 * hash leaves the device; never used for ads.
 */
@CapacitorPlugin(name = "DeviceIdentity")
public class DeviceIdentityPlugin extends Plugin {
    /** the id some old emulators/ROMs return for every device */
    private static final String BROKEN_ANDROID_ID = "9774d56d682e549c";

    @SuppressLint("HardwareIds")
    @PluginMethod
    public void getId(PluginCall call) {
        try {
            String androidId = Settings.Secure.getString(getContext().getContentResolver(), Settings.Secure.ANDROID_ID);
            if (androidId == null || androidId.isEmpty() || BROKEN_ANDROID_ID.equals(androidId)) {
                call.reject("Device identity unavailable");
                return;
            }
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(("worldos-device:" + androidId).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            // ROOT: the server only accepts ASCII hex, whatever the phone's language
            for (int i = 0; i < 20; i++) hex.append(String.format(Locale.ROOT, "%02x", digest[i]));
            JSObject result = new JSObject();
            result.put("id", "a_" + hex);
            call.resolve(result);
        } catch (Exception error) {
            call.reject("Device identity unavailable", error);
        }
    }
}
