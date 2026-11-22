#include "spell_checker.h"

#include <windows.h>
#include <objbase.h>
#include <spellcheck.h>

#include <flutter/standard_method_codec.h>

#include <map>
#include <string>
#include <variant>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::wstring ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

std::string ToUtf8(const wchar_t* w) {
  if (w == nullptr) return std::string();
  const int len = static_cast<int>(wcslen(w));
  if (len == 0) return std::string();
  const int n = WideCharToMultiByte(CP_UTF8, 0, w, len, nullptr, 0, nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w, len, s.data(), n, nullptr, nullptr);
  return s;
}

class SpellService {
 public:
  SpellService() = default;
  SpellService(const SpellService&) = delete;
  SpellService& operator=(const SpellService&) = delete;

  ~SpellService() {
    for (auto& entry : checkers_) {
      if (entry.second != nullptr) entry.second->Release();
    }
    if (factory_ != nullptr) factory_->Release();
  }

  EncodableList Languages() {
    EncodableList out;
    ISpellCheckerFactory* factory = Factory();
    if (factory == nullptr) return out;
    IEnumString* langs = nullptr;
    if (FAILED(factory->get_SupportedLanguages(&langs)) || langs == nullptr) return out;
    LPOLESTR lang = nullptr;
    while (langs->Next(1, &lang, nullptr) == S_OK) {
      out.push_back(EncodableValue(ToUtf8(lang)));
      CoTaskMemFree(lang);
      lang = nullptr;
    }
    langs->Release();
    return out;
  }

  // false = Sprache auf diesem PC nicht vorhanden.
  bool Check(const std::wstring& lang, const std::wstring& text, EncodableList& out) {
    ISpellChecker* checker = Checker(lang);
    if (checker == nullptr) return false;
    IEnumSpellingError* errors = nullptr;
    if (FAILED(checker->ComprehensiveCheck(text.c_str(), &errors)) || errors == nullptr) return true;
    ISpellingError* error = nullptr;
    while (errors->Next(&error) == S_OK && error != nullptr) {
      ULONG start = 0;
      ULONG length = 0;
      CORRECTIVE_ACTION action = CORRECTIVE_ACTION_NONE;
      error->get_StartIndex(&start);
      error->get_Length(&length);
      error->get_CorrectiveAction(&action);
      EncodableList suggestions;
      if (action == CORRECTIVE_ACTION_REPLACE) {
        LPWSTR replacement = nullptr;
        if (SUCCEEDED(error->get_Replacement(&replacement)) && replacement != nullptr) {
          suggestions.push_back(EncodableValue(ToUtf8(replacement)));
          CoTaskMemFree(replacement);
        }
      } else if (action == CORRECTIVE_ACTION_DELETE) {
        suggestions.push_back(EncodableValue(std::string()));
      } else if (action == CORRECTIVE_ACTION_GET_SUGGESTIONS &&
                 static_cast<size_t>(start) + length <= text.size()) {
        const std::wstring word = text.substr(start, length);
        IEnumString* list = nullptr;
        if (SUCCEEDED(checker->Suggest(word.c_str(), &list)) && list != nullptr) {
          LPOLESTR s = nullptr;
          int n = 0;
          while (n < 5 && list->Next(1, &s, nullptr) == S_OK) {
            suggestions.push_back(EncodableValue(ToUtf8(s)));
            CoTaskMemFree(s);
            s = nullptr;
            ++n;
          }
          list->Release();
        }
      }
      if (length > 0) {
        EncodableList entry;
        entry.push_back(EncodableValue(static_cast<int32_t>(start)));
        entry.push_back(EncodableValue(static_cast<int32_t>(length)));
        entry.push_back(EncodableValue(suggestions));
        out.push_back(EncodableValue(entry));
      }
      error->Release();
      error = nullptr;
    }
    errors->Release();
    return true;
  }

 private:
  ISpellCheckerFactory* Factory() {
    if (factory_ == nullptr && !factory_failed_) {
      if (FAILED(CoCreateInstance(__uuidof(SpellCheckerFactory), nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&factory_)))) {
        factory_ = nullptr;
        factory_failed_ = true;
      }
    }
    return factory_;
  }

  ISpellChecker* Checker(const std::wstring& lang) {
    auto it = checkers_.find(lang);
    if (it != checkers_.end()) return it->second;
    ISpellChecker* checker = nullptr;
    ISpellCheckerFactory* factory = Factory();
    BOOL supported = FALSE;
    if (factory != nullptr && SUCCEEDED(factory->IsSupported(lang.c_str(), &supported)) && supported) {
      if (FAILED(factory->CreateSpellChecker(lang.c_str(), &checker))) checker = nullptr;
    }
    checkers_[lang] = checker;
    return checker;
  }

  ISpellCheckerFactory* factory_ = nullptr;
  bool factory_failed_ = false;
  std::map<std::wstring, ISpellChecker*> checkers_;
};

const std::string* StringArg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(std::string(key)));
  if (it == args.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>> CreateSpellCheckChannel(
    flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "echowp/spell", &flutter::StandardMethodCodec::GetInstance());
  auto service = std::make_shared<SpellService>();
  channel->SetMethodCallHandler(
      [service](const flutter::MethodCall<EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "languages") {
          result->Success(EncodableValue(service->Languages()));
          return;
        }
        if (call.method_name() == "check") {
          const auto* args = std::get_if<EncodableMap>(call.arguments());
          const std::string* lang = args ? StringArg(*args, "lang") : nullptr;
          const std::string* text = args ? StringArg(*args, "text") : nullptr;
          if (lang == nullptr || text == nullptr) {
            result->Error("bad_args", "lang und text fehlen");
            return;
          }
          EncodableList out;
          if (!service->Check(ToWide(*lang), ToWide(*text), out)) {
            result->Success();  // null = Sprache nicht installiert
            return;
          }
          result->Success(EncodableValue(out));
          return;
        }
        result->NotImplemented();
      });
  return channel;
}
