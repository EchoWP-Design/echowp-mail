/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart';
import 'package:pointycastle/asn1.dart';

import '../../common/helpers.dart';
import '../../enum/hash_algorithm.dart';
import '../../type/verification_key_material.dart';
import 'ec_public_material.dart';

/// EdDSA legacy public key material
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
final class EdDSALegacyPublicMaterial extends ECPublicMaterial
    implements VerificationKeyMaterial {
  EdDSALegacyPublicMaterial(super.oid, super.q);

  factory EdDSALegacyPublicMaterial.fromBytes(
    final Uint8List bytes,
  ) {
    final length = bytes[0];
    return EdDSALegacyPublicMaterial(
      ASN1ObjectIdentifier.fromBytes(Uint8List.fromList([
        0x06,
        length,
        ...bytes.sublist(1, 1 + length),
      ])),
      Helper.readMPI(bytes.sublist(1 + length)),
    );
  }

  @override
  verify(
    final Uint8List message,
    final HashAlgorithm hash,
    final Uint8List signature,
  ) {
    // ECHOWP-PATCH: Länge aus dem MPI-Kopf lesen und r/s auf je 32 Byte auffüllen
    // (vorher scheiterte jede Signatur, deren r oder s mit 0x00 beginnt, ~1/128)
    final rLen = (signature.sublist(0, 2).unpack16() + 7) >> 3;
    final r = Helper.readMPI(signature);
    final s = Helper.readMPI(signature.sublist(rLen + 2));

    return VerifyKey(q.toUnsignedBytes().sublist(1)).verify(
      signature: Signature(Uint8List.fromList([
        ..._pad32(r),
        ..._pad32(s),
      ])),
      message: Helper.hashDigest(message, hash),
    );
  }
}

/// ECHOWP-PATCH: BigInt → genau 32 Byte (führende Nullen auffüllen).
Uint8List _pad32(BigInt v) {
  final b = v.toUnsignedBytes();
  if (b.length >= 32) return Uint8List.fromList(b.sublist(b.length - 32));
  return Uint8List(32)..setRange(32 - b.length, 32, b);
}
