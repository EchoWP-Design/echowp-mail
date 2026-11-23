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
# ---------- Windows: Dateien per Drag & Drop (WM_DROPFILES → Kanal "echowp/drop") ----------
def need(t: str, anchor: str, what: str) -> None:
    if anchor not in t:
        raise SystemExit(f"Drag & Drop: Ankerstelle fehlt in {what}: {anchor!r}")


def win_window_h(t: str) -> str:
    if "drop_channel_" in t:
        return t
    need(t, "#include <flutter/flutter_view_controller.h>", "flutter_window.h")
    need(t, "std::unique_ptr<flutter::FlutterViewController> flutter_controller_;", "flutter_window.h")
    t = t.replace(
        "#include <flutter/flutter_view_controller.h>",
        "#include <flutter/flutter_view_controller.h>\n#include <flutter/method_channel.h>\n#include <flutter/encodable_value.h>",
        1,
    )
    return t.replace(
        "std::unique_ptr<flutter::FlutterViewController> flutter_controller_;",
        "std::unique_ptr<flutter::FlutterViewController> flutter_controller_;\n\n"
        "  // Kanal für per Drag & Drop abgelegte Dateien\n"
        "  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> drop_channel_;",
        1,
    )


DROP_HANDLER = """  // Dateien aus dem Explorer ins Fenster gezogen → Pfade (UTF-8) an Dart melden
  if (message == WM_DROPFILES) {
    HDROP drop = reinterpret_cast<HDROP>(wparam);
    flutter::EncodableList files;
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      const UINT len = DragQueryFileW(drop, i, nullptr, 0);
      if (len == 0) continue;
      std::wstring path(len + 1, L'\\0');
      DragQueryFileW(drop, i, path.data(), len + 1);
      path.resize(len);
      const int size = WideCharToMultiByte(CP_UTF8, 0, path.c_str(), static_cast<int>(len), nullptr, 0, nullptr, nullptr);
      std::string utf8(size, '\\0');
      WideCharToMultiByte(CP_UTF8, 0, path.c_str(), static_cast<int>(len), utf8.data(), size, nullptr, nullptr);
      files.push_back(flutter::EncodableValue(utf8));
    }
    DragFinish(drop);
    if (drop_channel_ && !files.empty()) {
      drop_channel_->InvokeMethod("files", std::make_unique<flutter::EncodableValue>(files));
    }
    return 0;
  }

"""


def win_window_cpp(t: str) -> str:
    if "echowp/drop" in t:
        return t
    for a in ['#include "flutter_window.h"', "RegisterPlugins(flutter_controller_->engine());",
              "  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);",
              "    flutter_controller_ = nullptr;"]:
        need(t, a, "flutter_window.cpp")
    t = t.replace(
        '#include "flutter_window.h"',
        '#include "flutter_window.h"\n\n#include <shellapi.h>\n#include <string>\n\n#include <flutter/standard_method_codec.h>',
        1,
    )
    t = t.replace(
        "RegisterPlugins(flutter_controller_->engine());",
        "RegisterPlugins(flutter_controller_->engine());\n"
        "  drop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(\n"
        '      flutter_controller_->engine()->messenger(), "echowp/drop",\n'
        "      &flutter::StandardMethodCodec::GetInstance());\n"
        "  DragAcceptFiles(GetHandle(), TRUE);",
        1,
    )
    t = t.replace("    flutter_controller_ = nullptr;", "    drop_channel_ = nullptr;\n    flutter_controller_ = nullptr;", 1)
    return t.replace(
        "  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);",
        DROP_HANDLER + "  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);",
        1,
    )


patch(root / "windows/runner/flutter_window.h", win_window_h)
patch(root / "windows/runner/flutter_window.cpp", win_window_cpp)

# ---------- Windows: Rechtschreibprüfung (ISpellChecker) → Kanal "echowp/spell" ----------
import shutil

_win_runner = root / "windows/runner"
if _win_runner.exists():
    for _f in ("spell_checker.h", "spell_checker.cpp"):
        shutil.copyfile(root / "tool/windows" / _f, _win_runner / _f)
        print(f"kopiert: windows/runner/{_f}")


def win_runner_cmake(t: str) -> str:
    if "spell_checker.cpp" in t:
        return t
    need(t, '"flutter_window.cpp"', "runner/CMakeLists.txt")
    return t.replace('"flutter_window.cpp"', '"flutter_window.cpp"\n  "spell_checker.cpp"', 1)


def win_spell_h(t: str) -> str:
    if "spell_channel_" in t:
        return t
    need(t, "drop_channel_;", "flutter_window.h")
    return t.replace(
        "drop_channel_;",
        "drop_channel_;\n\n  // Kanal für die Windows-Rechtschreibprüfung\n"
        "  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> spell_channel_;",
        1,
    )


def win_spell_cpp(t: str) -> str:
    if "CreateSpellCheckChannel" in t:
        return t
    for a in ['#include <flutter/standard_method_codec.h>', "DragAcceptFiles(GetHandle(), TRUE);",
              "    drop_channel_ = nullptr;"]:
        need(t, a, "flutter_window.cpp")
    t = t.replace('#include <flutter/standard_method_codec.h>',
                  '#include <flutter/standard_method_codec.h>\n\n#include "spell_checker.h"', 1)
    t = t.replace("DragAcceptFiles(GetHandle(), TRUE);",
                  "DragAcceptFiles(GetHandle(), TRUE);\n"
                  "  spell_channel_ = CreateSpellCheckChannel(flutter_controller_->engine()->messenger());", 1)
    return t.replace("    drop_channel_ = nullptr;", "    spell_channel_ = nullptr;\n    drop_channel_ = nullptr;", 1)


patch(root / "windows/runner/CMakeLists.txt", win_runner_cmake)
patch(root / "windows/runner/flutter_window.h", win_spell_h)
patch(root / "windows/runner/flutter_window.cpp", win_spell_cpp)

print("Plattform-Anpassungen abgeschlossen.")
