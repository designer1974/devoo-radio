# WorkManager (usato dalla pubblicità Google) crea il suo database con Room per riflessione:
# senza queste regole la versione finale si chiude all'avvio ("Failed to create an instance of WorkDatabase").
-keep class androidx.work.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.** { *; }
-dontwarn androidx.work.**
