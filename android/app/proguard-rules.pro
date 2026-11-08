# Vosk / JNA 的 release 构建规则（v4.9.3）
#
# R8 会把 JNA 的 `Pointer.peer` 字段重命名成 `e` 之类的短名，而 JNA 的
# 原生层是用反射按名字取这个字段的，一旦改名，识别初始化就直接抛
#   Can't obtain peer field ID for class com.sun.jna.Pointer
# 这类错误只在 release 包里出现，debug 不复现，所以必须在这里保名。
-keep class com.sun.jna.** { *; }
-keep interface com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# Vosk 的 Java 绑定与 native 方法按名字查找，不能被裁剪 / 混淆。
-keep class org.vosk.** { *; }
-keep class com.alphacephei.** { *; }
-keepclassmembers class org.vosk.** { *; }

# 可选的平台库：桌面 / 其它架构用不到，缺了也不影响 Android。
-dontwarn java.awt.**
-dontwarn javax.swing.**
