package cc.worldos.app;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import androidx.annotation.RequiresApi;
import androidx.core.content.FileProvider;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Saves a file the page made (map timelapse video, share poster) to the phone's gallery. The
 * WebView ignores `<a download>` on a blob: URL and has no Web Share, so without this the page's
 * Download button does nothing. The page streams the bytes in base64 chunks (begin → append… →
 * finish) into this app's cache, then finish copies them into MediaStore — Movies/WorldOS or
 * Pictures/WorldOS — which needs no permission on Android 10+. Older Android opens the system
 * share sheet for the file instead. One file at a time: a new begin discards an unfinished one,
 * and every later call names its session, so a superseded save can't touch the new one.
 */
@CapacitorPlugin(name = "MediaSave")
public class MediaSavePlugin extends Plugin {
    private static final String CACHE_DIR = "media-save";
    /** the 48s 1080p video is ~27 MB; anything far past that is not ours */
    private static final long MAX_BYTES = 200L * 1024 * 1024;
    private static final List<String> MIME_TYPES = Arrays.asList("video/mp4", "video/webm", "image/png", "image/jpeg");

    private String sessionId;
    private File pendingFile;
    private String pendingMime;
    private long written;

    @PluginMethod
    public void begin(PluginCall call) {
        // a codecs parameter ("video/webm;codecs=vp9") is not part of the gallery's type
        String mime = call.getString("mimeType", "").split(";")[0].trim().toLowerCase(Locale.ROOT);
        if (!MIME_TYPES.contains(mime)) {
            call.reject("Unsupported media type");
            return;
        }
        try {
            File dir = new File(getContext().getCacheDir(), CACHE_DIR);
            File[] stale = dir.listFiles();
            if (stale != null) for (File f : stale) f.delete();
            if (!dir.isDirectory() && !dir.mkdirs()) throw new Exception("cache dir");
            pendingFile = new File(dir, safeName(call.getString("fileName", "")));
            new FileOutputStream(pendingFile).close();
            pendingMime = mime;
            written = 0;
            sessionId = UUID.randomUUID().toString();
            JSObject result = new JSObject();
            result.put("id", sessionId);
            call.resolve(result);
        } catch (Exception error) {
            discard();
            call.reject("Media save unavailable", error);
        }
    }

    @PluginMethod
    public void append(PluginCall call) {
        if (!isCurrent(call)) return;
        try {
            byte[] bytes = Base64.decode(call.getString("data", ""), Base64.DEFAULT);
            if (written + bytes.length > MAX_BYTES) throw new Exception("too large");
            try (OutputStream out = new FileOutputStream(pendingFile, true)) {
                out.write(bytes);
            }
            written += bytes.length;
            call.resolve();
        } catch (Exception error) {
            discard();
            call.reject("Media save failed", error);
        }
    }

    @PluginMethod
    public void finish(PluginCall call) {
        if (!isCurrent(call)) return;
        File file = pendingFile;
        String mime = pendingMime;
        boolean empty = written == 0;
        reset();
        try {
            if (empty) throw new Exception("empty");
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveToGallery(file, mime);
                file.delete();
                JSObject result = new JSObject();
                result.put("savedTo", "gallery");
                call.resolve(result);
                return;
            }
            // Android 9 and older need a storage permission to write the gallery; the share
            // sheet hands the file to an app the player picks instead (the file stays in the
            // cache for that app to read, and the next begin clears it)
            Uri uri = FileProvider.getUriForFile(getContext(), getContext().getPackageName() + ".fileprovider", file);
            Intent send = new Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            getActivity().runOnUiThread(() -> {
                try {
                    getActivity().startActivity(Intent.createChooser(send, null));
                    JSObject result = new JSObject();
                    result.put("savedTo", "share");
                    call.resolve(result);
                } catch (Exception error) {
                    file.delete();
                    call.reject("Media save failed", error);
                }
            });
        } catch (Exception error) {
            if (file != null) file.delete();
            call.reject("Media save failed", error);
        }
    }

    /** drops the named save's partial file; a superseded or finished save is left alone */
    @PluginMethod
    public void cancel(PluginCall call) {
        if (sessionId != null && sessionId.equals(call.getString("id"))) discard();
        call.resolve();
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private void saveToGallery(File file, String mime) throws Exception {
        boolean video = mime.startsWith("video/");
        ContentResolver resolver = getContext().getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, file.getName());
        values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
        values.put(
            MediaStore.MediaColumns.RELATIVE_PATH,
            (video ? Environment.DIRECTORY_MOVIES : Environment.DIRECTORY_PICTURES) + "/WorldOS"
        );
        values.put(MediaStore.MediaColumns.IS_PENDING, 1);
        Uri collection = video
            ? MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            : MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
        Uri item = resolver.insert(collection, values);
        if (item == null) throw new Exception("insert failed");
        try {
            try (InputStream in = new FileInputStream(file); OutputStream out = resolver.openOutputStream(item)) {
                if (out == null) throw new Exception("open failed");
                byte[] buffer = new byte[64 * 1024];
                for (int n; (n = in.read(buffer)) > 0; ) out.write(buffer, 0, n);
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.MediaColumns.IS_PENDING, 0);
            // a row left pending stays hidden from the gallery (the system purges it later)
            if (resolver.update(item, done, null, null) != 1) throw new Exception("publish failed");
        } catch (Exception error) {
            resolver.delete(item, null, null);
            throw error;
        }
    }

    /** rejects a call from an abandoned or superseded save */
    private boolean isCurrent(PluginCall call) {
        if (sessionId != null && sessionId.equals(call.getString("id"))) return true;
        call.reject("No media save in progress");
        return false;
    }

    /** forgets the save and deletes its partial file */
    private void discard() {
        if (pendingFile != null) pendingFile.delete();
        reset();
    }

    private void reset() {
        sessionId = null;
        pendingFile = null;
        pendingMime = null;
        written = 0;
    }

    /** the page's file name, reduced to characters every gallery and file system accepts */
    private static String safeName(String name) {
        String clean = name.replaceAll("[^A-Za-z0-9._-]", "_");
        // keep the tail (the extension); a leading dot would hide the file
        if (clean.length() > 120) clean = clean.substring(clean.length() - 120);
        if (clean.isEmpty() || clean.startsWith(".")) clean = "worldos" + clean;
        return clean;
    }
}
