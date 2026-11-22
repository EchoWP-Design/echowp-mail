// Windows-Rechtschreibprüfung (ISpellChecker) für EchoWP-Mail.
// Kanal "echowp/spell": "languages" -> Liste der Sprach-Tags,
// "check" {lang, text} -> [[start, länge, [vorschläge]], ...] oder null (Sprache fehlt).
#ifndef RUNNER_SPELL_CHECKER_H_
#define RUNNER_SPELL_CHECKER_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateSpellCheckChannel(
    flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SPELL_CHECKER_H_
