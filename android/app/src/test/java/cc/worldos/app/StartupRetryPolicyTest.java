package cc.worldos.app;

import org.junit.Test;
import static org.junit.Assert.*;

public class StartupRetryPolicyTest {
    private static final String HOME = "https://worldos.cc/zh-cn";

    @Test
    public void recoversFirstConnectionRefusalWithoutTreatingErrorCommitAsSuccess() {
        StartupRetryPolicy policy = new StartupRetryPolicy("https://worldos.cc", 0);
        policy.onPageStarted(HOME);
        assertEquals(250, policy.retryDelay(HOME, true, -6, 100));
        assertTrue(policy.shouldIgnoreCommit(HOME, true));
        assertFalse(policy.onPageCommitted(HOME, true));
        assertFalse(policy.onPageCommitted(HOME, false));
        policy.onPageStarted(HOME);
        assertFalse(policy.shouldIgnoreCommit(HOME, false));
        assertTrue(policy.onPageCommitted(HOME, false));
        assertEquals(-1, policy.retryDelay(HOME, true, -6, 1000));
    }

    @Test
    public void genuinelyOfflineStartupHasAFiniteBudgetAndDeadline() {
        StartupRetryPolicy policy = new StartupRetryPolicy("https://worldos.cc", 100);
        assertEquals(250, policy.retryDelay(HOME, true, -6, 200));
        assertEquals(750, policy.retryDelay(HOME, true, -6, 500));
        assertEquals(-1, policy.retryDelay(HOME, true, -6, 1400));
        assertEquals(2, policy.attempts());
        assertFalse(policy.canRunRetry(10100));
        StartupRetryPolicy late = new StartupRetryPolicy("https://worldos.cc", 0);
        assertEquals(-1, late.retryDelay(HOME, true, -8, 9900));
    }

    @Test
    public void neverRetriesSubresourcesOtherOriginsOrSecurityErrors() {
        StartupRetryPolicy policy = new StartupRetryPolicy("https://worldos.cc", 0);
        assertEquals(-1, policy.retryDelay(HOME, false, -6, 100));
        assertEquals(-1, policy.retryDelay("https://localhost/offline.html", true, -6, 100));
        assertEquals(-1, policy.retryDelay("https://go.worldos.cc/link", true, -6, 100));
        assertEquals(-1, policy.retryDelay("http://worldos.cc/", true, -6, 100));
        assertEquals(-1, policy.retryDelay("https://worldos.cc:444/", true, -6, 100));
        assertEquals(-1, policy.retryDelay("https://user:pass@worldos.cc/", true, -6, 100));
        for (int error : new int[]{-1, -4, -5, -9, -10, -11, -16}) {
            assertEquals(-1, policy.retryDelay(HOME, true, error, 100));
        }
        assertEquals(0, policy.attempts());
    }

    @Test
    public void keepsTheConfiguredOriginAndAcceptsPathsQueriesAndExplicitDefaultPorts() {
        StartupRetryPolicy policy = new StartupRetryPolicy("https://worldos.cc", 0);
        assertTrue(policy.isServiceUrl("https://WORLDOS.cc:443/zh-cn/world/123?ref=example#start"));
        assertFalse(policy.isServiceUrl("https://worldos.cc.example.com/"));
        StartupRetryPolicy dev = new StartupRetryPolicy("http://127.0.0.1:3000", 0);
        assertTrue(dev.isServiceUrl("http://127.0.0.1:3000/preview?existing=1"));
        assertFalse(dev.isServiceUrl("http://127.0.0.1:3001/"));
        assertFalse(new StartupRetryPolicy(null, 0).isServiceUrl(HOME));
        assertFalse(new StartupRetryPolicy("invalid", 0).isServiceUrl(HOME));
    }

    @Test
    public void terminalFailureOrDestroyCancelsRecovery() {
        StartupRetryPolicy policy = new StartupRetryPolicy("https://worldos.cc", 0);
        policy.retryDelay(HOME, true, -6, 100);
        policy.finish();
        assertFalse(policy.canRunRetry(500));
        assertEquals(-1, policy.retryDelay(HOME, true, -6, 500));
        assertFalse(policy.onPageCommitted(HOME, false));
    }
}
