# WorkManager (usato dalla pubblicità Google) crea il suo database con Room per riflessione:
# senza queste regole la versione finale si chiude all'avvio ("Failed to create an instance of WorkDatabase").
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.** { *; }
-dontwarn androidx.work.**

# ML Kit (traduzione, riconoscimento lingua) usa la "reflection"
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_** { *; }
-keep class com.google.firebase.components.** { *; }
-keepclassmembers class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
# Whisper / FFmpeg (codice nativo chiamato da Java)
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.** { *; }
-dontwarn com.arthenica.**
# Voce del telefono
-keep class com.tundralabs.fluttertts.** { *; }
