package cc.worldos.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.PluginCall;
import com.getcapacitor.community.admob.models.AdOptions;
import com.getcapacitor.community.admob.rewarded.models.SsvInfo;
import com.getcapacitor.community.admob.rewardedinterstitial.RewardedInterstitialAdCallbackAndListeners;
import com.google.android.gms.ads.rewarded.ServerSideVerificationOptions;
import com.google.android.gms.ads.rewardedinterstitial.RewardedInterstitialAd;
import com.google.android.gms.common.util.BiConsumer;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class RewardedInterstitialSsvTest {
    private static final String USER = "00000000-0000-4000-8000-000000000001";
    private static final String SESSION = "00000000-0000-4000-8000-000000000002";

    @Test void attachesBothFieldsBeforeResolvingPreparation() {
        checkSsv(USER, SESSION);
    }

    @Test void acceptsUserIdWithoutCustomData() {
        checkSsv(USER, null);
    }

    @Test void acceptsCustomDataWithoutUserId() {
        checkSsv(null, SESSION);
    }

    @Test void missingSsvDoesNotBreakOrdinaryAdLoading() {
        checkSsv(null, null);
    }

    @SuppressWarnings("unchecked")
    private void checkSsv(String userId, String customData) {
        PluginCall call = mock(PluginCall.class);
        BiConsumer<String, JSObject> listeners = mock(BiConsumer.class);
        RewardedInterstitialAd ad = mock(RewardedInterstitialAd.class);
        when(ad.getAdUnitId()).thenReturn("test-interstitial-unit");
        AdOptions options = new AdOptions.TesterAdOptionsBuilder()
            .setSsvInfo(new SsvInfo(customData, userId)).build();

        RewardedInterstitialAdCallbackAndListeners.INSTANCE
            .getRewardedAdLoadCallback(call, listeners, options).onAdLoaded(ad);

        if (userId == null && customData == null) {
            verify(ad, never()).setServerSideVerificationOptions(any());
            verify(call).resolve(any(JSObject.class));
            return;
        }
        ArgumentCaptor<ServerSideVerificationOptions> captured =
            ArgumentCaptor.forClass(ServerSideVerificationOptions.class);
        InOrder order = inOrder(ad, call, listeners);
        order.verify(ad).setServerSideVerificationOptions(captured.capture());
        order.verify(call).resolve(any(JSObject.class));
        order.verify(listeners).accept(any(String.class), any(JSObject.class));
        assertEquals(userId == null ? "" : userId, captured.getValue().getUserId());
        assertEquals(customData == null ? "" : customData, captured.getValue().getCustomData());
    }
}
