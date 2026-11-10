# Release keep rules for cc.worldos.app (R8 is on for release builds).
#
# Already covered by the libraries' own consumer rules, so not repeated here:
# Capacitor (@CapacitorPlugin classes, Plugin subclasses incl. our own plugins,
# Cordova plugins such as OneSignal), social-login (com.getcapacitor.**, okhttp,
# Google sign-in), Firebase, OneSignal, Play Billing, play-services-ads.
# @JavascriptInterface members are kept by proguard-android-optimize.txt.

# Readable crash stacks: Play deobfuscates with the mapping bundled in the AAB.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# AppsFlyer (vendor-documented rules).
-keep class com.appsflyer.** { *; }
-keep public class com.android.installreferrer.** { *; }

# AdMob mediation loads adapters by class name.
-keep class com.google.ads.mediation.unity.** { *; }
-keep class com.unity3d.ads.** { *; }
-keep class com.unity3d.services.** { *; }

# RevenueCat ships consumer rules; kept explicitly because purchases are revenue-critical.
-keep class com.revenuecat.purchases.** { *; }
