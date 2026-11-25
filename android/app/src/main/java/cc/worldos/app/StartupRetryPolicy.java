package cc.worldos.app;

import java.net.URI;

/** A bounded recovery window for the configured service's first document. */
final class StartupRetryPolicy {
    private static final long STARTUP_WINDOW_MS = 10_000;
    private static final long[] RETRY_DELAYS_MS = {250, 750};

    private final URI service;
    private final long startedAt;
    private int attempts;
    private boolean finished;
    private boolean currentLoadFailed;

    StartupRetryPolicy(String serverUrl, long startedAt) {
        URI parsed = null;
        try {
            if (serverUrl != null) parsed = URI.create(serverUrl);
        } catch (IllegalArgumentException ignored) {}
        service = parsed;
        this.startedAt = startedAt;
    }

    boolean isServiceUrl(String url) {
        if (service == null || service.getHost() == null || url == null) return false;
        try {
            URI candidate = URI.create(url);
            String scheme = service.getScheme();
            return ("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
                && scheme.equalsIgnoreCase(candidate.getScheme())
                && service.getHost().equalsIgnoreCase(candidate.getHost())
                && effectivePort(service) == effectivePort(candidate)
                && candidate.getRawUserInfo() == null;
        } catch (IllegalArgumentException ignored) {
            return false;
        }
    }

    private static int effectivePort(URI uri) {
        return uri.getPort() >= 0 ? uri.getPort() : ("https".equalsIgnoreCase(uri.getScheme()) ? 443 : 80);
    }

    void onPageStarted(String url) {
        if (isServiceUrl(url)) currentLoadFailed = false;
    }

    long retryDelay(String url, boolean mainFrame, int errorCode, long now) {
        if (!mainFrame || !isServiceUrl(url)) return -1;
        currentLoadFailed = true;
        // Android WebView: HOST_LOOKUP, CONNECT, IO, TIMEOUT. Certificate,
        // authentication, unsafe-resource and HTTP errors keep normal handling.
        boolean transientFailure = errorCode == -2 || errorCode == -6 || errorCode == -7 || errorCode == -8;
        if (finished || !transientFailure || attempts >= RETRY_DELAYS_MS.length) return -1;
        long delay = RETRY_DELAYS_MS[attempts];
        if (now - startedAt + delay >= STARTUP_WINDOW_MS) return -1;
        attempts++;
        return delay;
    }

    boolean canRunRetry(long now) {
        return !finished && now - startedAt < STARTUP_WINDOW_MS;
    }

    boolean onPageCommitted(String url, boolean retryPending) {
        if (finished || currentLoadFailed || retryPending || !isServiceUrl(url)) return false;
        finished = true;
        return true;
    }

    boolean shouldIgnoreCommit(String url, boolean retryPending) {
        return isServiceUrl(url) && (currentLoadFailed || retryPending);
    }

    int attempts() {
        return attempts;
    }

    void finish() {
        finished = true;
    }
}
