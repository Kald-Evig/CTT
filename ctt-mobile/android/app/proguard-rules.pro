# Keep rules del proyecto (CTT).
# R8 full mode (default en AGP 8+) elimina constructores no referenciados
# estáticamente. Room instancia sus subclases *_Impl por reflexión.

# --- Room / WorkManager -------------------------------------------------------
# La consumer rule de room-runtime 2.6.1 es `-keep class * extends
# androidx.room.RoomDatabase` SIN conservar <init>(). En full mode eso borra el
# constructor de WorkDatabase_Impl y WorkManager crashea al arrancar
# (NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []).
# Conservar el constructor de toda subclase de RoomDatabase lo cubre por
# herencia, incluidas las clases *_Impl generadas.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}

# --- Firebase --------------------------------------------------------------------
# Firebase descubre sus módulos instanciando por reflexión las clases que
# implementan ComponentRegistrar (CrashlyticsRegistrar, FirebaseInstallations
# KtxRegistrar, etc.). La consumer rule de firebase-common (configuration.txt:634)
# es `-keep class * implements ...ComponentRegistrar` SIN <init>(): en full mode
# R8 borra el constructor y ComponentDiscovery falla con NoSuchMethodException
# -> "FirebaseCrashlytics component is not present" -> Firebase.initializeApp()
# lanza y main() muere antes de runApp(): la app queda pegada en el splash.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
