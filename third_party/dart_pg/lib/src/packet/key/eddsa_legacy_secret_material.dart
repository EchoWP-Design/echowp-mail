/// Copyright 2024-present by Dart Privacy Guard project. All rights reserved.
/// For the full copyright and license information, please view the LICENSE
/// file that was distributed with this source code.

library;

import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pinenacl/tweetnacl.dart';

import '../../common/helpers.dart';
import '../../enum/ecc.dart';
import '../../enum/hash_algorithm.dart';
import '../../type/signing_key_material.dart';
import 'eddsa_legacy_public_material.dart';

/// EdDSA legacy secret key material
/// Author Nguyen Van Nguyen <nguyennv1981@gmail.com>
final class EdDSALegacySecretMaterial implements SigningKeyMaterialInterface {
  /// Ed's seed parameter
  final BigInt seed;

  @override
  final EdDSALegacyPublicMaterial publicMaterial;

  EdDSALegacySecretMaterial(this.seed, this.publicMaterial);

  factory EdDSALegacySecretMaterial.fromBytes(
    final Uint8List bytes,
    final EdDSALegacyPublicMaterial publicMaterial,
  ) =>
      EdDSALegacySecretMaterial(
        Helper.readMPI(bytes),
        publicMaterial,
      );

  factory EdDSALegacySecretMaterial.generate() {
    final seed = Helper.randomBytes(TweetNaCl.seedSize);
    return EdDSALegacySecretMaterial(
      seed.toUnsignedBigInt(),
      EdDSALegacyPublicMaterial(
          Ecc.ed25519.asn1Oid,
          Uint8List.fromList([
            0x40,
            ...nacl.SigningKey.fromSeed(seed).verifyKey.asTypedList,
          ]).toUnsignedBigInt()),
    );
  }

  @override
  get isValid {
    final signingKey = nacl.SigningKey.fromSeed(
      _seed32(seed), // ECHOWP-PATCH: führende Nullbytes erhalten
    );
    final dG = Uint8List.fromList([
      0x40,
      ...signingKey.verifyKey.asTypedList,
    ]);
    return publicMaterial.q.compareTo(dG.toUnsignedBigInt()) == 0;
  }

  @override
  get keyStrength => publicMaterial.keyStrength;

  @override
  sign(Uint8List message, HashAlgorithm hash) {
    final signed = nacl.SigningKey.fromSeed(
      _seed32(seed), // ECHOWP-PATCH: führende Nullbytes erhalten
    ).sign(
      Helper.hashDigest(message, hash),
    );
    // ECHOWP-PATCH: r und s als korrekte MPIs (ohne führende Nullbytes, mit echter Bitlänge)
    final half = nacl.SignedMessage.signatureLength ~/ 2;
    final r = Uint8List.fromList(signed.signature.sublist(0, half)).toUnsignedBigInt();
    final s = Uint8List.fromList(signed.signature.sublist(half)).toUnsignedBigInt();
    return Uint8List.fromList([
      ...r.bitLength.pack16(),
      ...r.toUnsignedBytes(),
      ...s.bitLength.pack16(),
      ...s.toUnsignedBytes(),
    ]);
  }

  @override
  get toBytes => Uint8List.fromList([
        ...seed.bitLength.pack16(),
        ...seed.toUnsignedBytes(),
      ]);
}

/// ECHOWP-PATCH: BigInt → genau 32 Byte (führende Nullen auffüllen).
Uint8List _seed32(BigInt seed) {
  final b = seed.toUnsignedBytes();
  if (b.length >= 32) return Uint8List.fromList(b.sublist(b.length - 32));
  return Uint8List(32)..setRange(32 - b.length, 32, b);
}
