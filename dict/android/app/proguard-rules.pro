# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# R8 (minifyEnabled) for the release build. Everything the WebView / Capacitor reaches by NAME at run time must survive renaming.
# Capacitor finds a plugin by its @CapacitorPlugin annotation and calls the @PluginMethod methods through reflection.
-keep class com.getcapacitor.** { *; }
-keep @com.getcapacitor.annotation.CapacitorPlugin public class * { @com.getcapacitor.annotation.PermissionCallback <methods>; @com.getcapacitor.annotation.ActivityCallback <methods>; @com.getcapacitor.PluginMethod public <methods>; }
-keep public class * extends com.getcapacitor.Plugin
# Our own classes: plugins, services, receivers and the activities named in the manifest.
-keep class gift.dhamma.pali.** { *; }
# The page calls @JavascriptInterface methods by name.
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }
# Readable crash traces in Play's console (upload mapping.txt from the build).
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-renamesourcefileattribute SourceFile
