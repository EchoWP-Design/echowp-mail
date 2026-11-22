# dart_pg 2.0.0 – EchoWP-Patches

Kopie von https://github.com/web-of-trust/dart-pg (Tag 2.0.0, BSD-3-Lizenz, siehe LICENSE).
Alle Änderungen (8 Patches) sind im Code mit `ECHOWP-PATCH` markiert.

1. `packet/signature.dart` `_keySubpackets`: v4-Schlüssel werben nur mit SEIPDv1 (Features 0x01) und ohne
   bevorzugte AEAD-Algorithmen. Vorher 0x0B (AEAD + SEIPDv2) → Thunderbird/Betterbird: „Einige der importierten
   Geheimschlüssel machen eine nicht unterstützte Funktion bekannt“.
2. `message/literal_message.dart` `generateSessionKey`: AEAD/SEIPDv2 nur bei `Config.aeadProtect` (aus), nicht
   automatisch, wenn alle Empfängerschlüssel es anbieten – sonst kann Thunderbird die Mail nicht lesen.
3. `packet/key/eddsa_legacy_secret_material.dart`: Ed25519-Seed immer auf 32 Byte auffüllen. Vorher scheiterten
   Schlüssel, deren Seed mit 0x00 beginnt (~1/256), mit „SigningKey must be created from a 32 byte seed“.
4. `packet/key/eddsa_legacy_public_material.dart` `verify`: r/s-Länge aus dem MPI-Kopf, beide auf 32 Byte
   aufgefüllt. Vorher wurde jede Ed25519-Signatur, deren r oder s mit 0x00 beginnt (~1/128), als ungültig
   gewertet – auch Signaturen aus Thunderbird/GnuPG.
5. `packet/key/eddsa_legacy_secret_material.dart` `sign`: r und s als korrekte MPIs (echte Bitlänge).
6. `message/signature.dart` `verify`: Textsignaturen (Typ 0x01) über kanonischen Text (LF → CRLF) prüfen.
   Vorher waren Signaturen aus Betterbird/Thunderbird in verschlüsselten Mails „ungültig“.
7. `packet/signature.dart` `expirationTime`: Ablauf = Erstellung + Sekunden, 0 = nie. Vorher als festes Datum
   gelesen → Signaturen aus Thunderbird/Betterbird (RNP schreibt immer 0) galten als abgelaufen = „ungültig“.
8. `common/armor.dart` `Armor.decode`: CRLF/CR-Zeilenenden akzeptieren. Vorher „Unknown ASCII armor type“ bei
   Schlüsseln aus Betterbird/RNP und Windows-Dateien.

Bei einem Update von dart_pg: neue Version hierher kopieren und die drei Patches erneut prüfen.
