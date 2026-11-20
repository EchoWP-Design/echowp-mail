"""Passt die von `flutter create` erzeugten Plattform-Dateien an (läuft im GitHub-Build)."""
import os
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent


def patch(path: pathlib.Path, fn):
    if not path.exists():
        print(f"übersprungen (fehlt): {path}")
        return
    old = path.read_text(encoding="utf-8")
    new = fn(old)
    if new != old:
        path.write_text(new, encoding="utf-8")
        print(f"angepasst: {path.relative_to(root)}")


# ---------- Android: Manifest ----------
def manifest(t: str) -> str:
    t = re.sub(r'android:label="[^"]*"', 'android:label="EchoWP-Mail"', t, count=1)
    # Keine Android-Cloud-/ADB-Sicherung der App-Daten (Konten, Tokens)
    if "android:allowBackup" not in t:
        t = t.replace("<application", '<application\n        android:allowBackup="false"\n        android:fullBackupContent="false"', 1)
    # Push-Dienst (IMAP IDLE) als Vordergrunddienst vom Typ „remoteMessaging“
    if "id.flutter.flutter_background_service.BackgroundService" not in t:
        t = t.replace(
            "</application>",
            '    <service\n'
            '            android:name="id.flutter.flutter_background_service.BackgroundService"\n'
            '            android:foregroundServiceType="remoteMessaging" />\n'
            "    </application>",
            1,
        )
    # Knöpfe in Benachrichtigungen (Löschen / Als gelesen / Antworten)
    if "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" not in t:
        t = t.replace(
            "</application>",
            '    <receiver\n'
            '            android:exported="false"\n'
            '            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />\n'
            "    </application>",
            1,
        )
    for perm in [
        "android.permission.INTERNET",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING",
        "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    ]:
        if perm not in t:
            t = t.replace("<application", f'<uses-permission android:name="{perm}"/>\n    <application', 1)
    return t


patch(root / "android/app/src/main/AndroidManifest.xml", manifest)

STORE = "../../keystore/echowp-release.jks"
PW = os.environ.get("ANDROID_KEYSTORE_PASSWORD", "")


# ---------- Android: Gradle (Kotlin DSL) ----------
def gradle_kts(t: str) -> str:
    if "isCoreLibraryDesugaringEnabled" not in t:
        t = t.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    t = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", t)
    if 'create("release")' not in t:
        signing = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            f'            storeFile = file("{STORE}")\n'
            f'            storePassword = "{PW}"\n'
            '            keyAlias = "echowp"\n'
            f'            keyPassword = "{PW}"\n'
            "        }\n"
            "    }\n\n"
        )
        t = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + signing.rstrip("\n") + r"\1", t, count=1)
    t = t.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
    if "desugar_jdk_libs" not in t:
        t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    return t


# ---------- Android: Gradle (Groovy, ältere Flutter-Versionen) ----------
def gradle_groovy(t: str) -> str:
    if "coreLibraryDesugaringEnabled" not in t:
        t = t.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    t = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdkVersion 24", t)
    if "signingConfigs {" not in t:
        signing = (
            "    signingConfigs {\n"
            "        release {\n"
            f'            storeFile file("{STORE}")\n'
            f'            storePassword "{PW}"\n'
            '            keyAlias "echowp"\n'
            f'            keyPassword "{PW}"\n'
            "        }\n"
            "    }\n"
        )
        t = re.sub(r"(\n\s*buildTypes\s*\{)", "\n" + signing.rstrip("\n") + r"\1", t, count=1)
    t = t.replace("signingConfig = signingConfigs.debug", "signingConfig = signingConfigs.release")
    t = t.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    if "desugar_jdk_libs" not in t:
        t += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    return t


patch(root / "android/app/build.gradle.kts", gradle_kts)


# ---------- Android: alle Plugins gegen SDK 36 kompilieren (file_picker nutzt sonst 34) ----------
ROOT_KTS_BLOCK = """
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                // Nur anheben (mind. 36), nie absenken – manche Plugins brauchen neuere SDKs
                val current = androidExt.javaClass.getMethod("getCompileSdkVersion").invoke(androidExt) as String?
                val level = current?.substringAfter("android-")?.toIntOrNull() ?: 0
                if (level < 36) {
                    androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(androidExt, 36)
                }
            } catch (e: Exception) {
                println("compileSdk-Anpassung übersprungen: " + project.name)
            }
        }
    }
}
"""


def root_kts(t: str) -> str:
    if "compileSdk-Anpassung" in t:
        return t
    marker = "subprojects {\n    project.evaluationDependsOn"
    if marker in t:
        return t.replace(marker, ROOT_KTS_BLOCK.lstrip("\n") + "\n" + marker, 1)
    return ROOT_KTS_BLOCK + "\n" + t


patch(root / "android/build.gradle.kts", root_kts)
patch(root / "android/app/build.gradle", gradle_groovy)

# ---------- Windows: neuere MSVC-Versionen brechen sonst beim Benachrichtigungs-Plugin ab ----------
def win_cmake(t: str) -> str:
    define = "add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)"
    if define not in t:
        t = re.sub(r"(project\([^\n]*\)\n)", r"\1" + define + "\n", t, count=1)
    return t


patch(root / "windows/CMakeLists.txt", win_cmake)

# ---------- Windows: Fenstertitel ----------
patch(root / "windows/runner/main.cpp", lambda t: t.replace('L"echowp_mail"', 'L"EchoWP-Mail"'))
patch(
    root / "windows/runner/Runner.rc",
    lambda t: t.replace('"FileDescription", "echowp_mail"', '"FileDescription", "EchoWP-Mail"').replace(
        '"ProductName", "echowp_mail"', '"ProductName", "EchoWP-Mail"'
    ),
)
print("Plattform-Anpassungen abgeschlossen.")
