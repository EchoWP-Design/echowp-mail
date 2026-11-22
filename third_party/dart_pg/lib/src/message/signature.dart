/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'dart:typed_data';

import '../common/armor.dart';
import '../common/helpers.dart';
import '../enum/armor_type.dart';
import '../enum/hash_algorithm.dart';
import '../enum/signature_type.dart';
import '../message/verification.dart';
import '../packet/base_packet.dart';
import '../type/cleartext_message.dart';
import '../type/key.dart';
import '../type/literal_data.dart';
import '../type/signature.dart';
import '../type/signature_packet.dart';
import '../type/verification.dart';

/// Signature class
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
final class Signature implements SignatureInterface {
  @override
  final Iterable<SignaturePacketInterface> packets;

  Signature(this.packets);

  /// Read signature from armored string
  factory Signature.fromArmored(final String armored) {
    final armor = Armor.decode(armored).assertType(ArmorType.signature);
    return Signature(
      PacketList.decode(armor.data).whereType<SignaturePacketInterface>(),
    );
  }

  @override
  Iterable<HashAlgorithm> get hashAlgorithms => packets.map(
        (packet) => packet.hashAlgorithm,
      );

  @override
  get packetList => PacketList(packets);

  @override
  get signingKeyIDs => packets.map(
        (signature) => signature.issuerKeyID,
      );

  @override
  armor() => Armor.encode(ArmorType.signature, packetList.encode());

  @override
  Iterable<VerificationInterface> verify(
    final Iterable<KeyInterface> verificationKeys,
    final LiteralDataInterface literalData, [
    final DateTime? time,
  ]) {
    if (verificationKeys.isEmpty) {
      throw ArgumentError(
        'No verification keys provided.',
      );
    }
    final verifications = <VerificationInterface>[];
    for (final packet in packets) {
      for (final key in verificationKeys) {
        final keyPacket = key.publicKey.keyPacket;
        if (packet.issuerKeyID.equals(keyPacket.keyID)) {
          var isVerified = false;
          var verificationError = '';
          try {
            isVerified = packet.verify(
              keyPacket,
              _signedBytes(packet, literalData), // ECHOWP-PATCH
              time,
            );
          } on Error catch (error) {
            verificationError = error.toString();
          }

          verifications.add(
            Verification(
              keyPacket.keyID,
              packet,
              isVerified,
              verificationError,
              key.users.where((user) => user.userID.isNotEmpty).map(
                    (user) => user.userID,
                  ),
            ),
          );
        }
      }
    }
    return verifications;
  }

  @override
  verifyCleartext(
    final Iterable<KeyInterface> verificationKeys,
    final CleartextMessageInterface cleartext, [
    final DateTime? time,
  ]) {
    return verify(
      verificationKeys,
      LiteralDataPacket.fromText(cleartext.text),
      time,
    );
  }
}

/// ECHOWP-PATCH: Textsignaturen (Typ 0x01) werden über kanonischen Text gebildet –
/// einzelne LF werden dabei zu CRLF (RFC 9580 5.2.1.2). Thunderbird/Betterbird signiert so.
Uint8List _signedBytes(SignaturePacketInterface packet, LiteralDataInterface data) {
  final b = data.binary;
  if (packet.signatureType != SignatureType.text || b.isEmpty) return data.signBytes;
  final out = <int>[];
  for (var i = 0; i < b.length; i++) {
    if (b[i] == 0x0A && (i == 0 || b[i - 1] != 0x0D)) out.add(0x0D);
    out.add(b[i]);
  }
  return Uint8List.fromList(out);
}
