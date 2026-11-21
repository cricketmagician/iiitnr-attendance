import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

/// The phone's identity for the device lock: a random device ID and a P-256
/// key pair created on first use. The private key never leaves the phone; it
/// is kept in the Android Keystore / iOS Keychain through flutter_secure_storage.
/// Every request is signed with it, so a copied password or request is useless
/// on another phone.
class DeviceIdentity {
  static const _kDeviceId = 'att_device_id';
  static const _kPrivate = 'att_private_d';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static final _domain = ECDomainParameters('secp256r1');

  String? _deviceId;
  ECPrivateKey? _private;
  ECPublicKey? _public;

  Future<void> ensure() async {
    if (_private != null) return;
    _deviceId = await _storage.read(key: _kDeviceId);
    final d = await _storage.read(key: _kPrivate);
    if (_deviceId == null || d == null) {
      await _create();
      return;
    }
    _private = ECPrivateKey(BigInt.parse(d, radix: 16), _domain);
    _public = ECPublicKey(_domain.G * _private!.d, _domain);
  }

  Future<void> _create() async {
    final rnd = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)))));
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_domain), rnd));
    final pair = gen.generateKeyPair();
    _private = pair.privateKey as ECPrivateKey;
    _public = pair.publicKey as ECPublicKey;
    _deviceId = const Uuid().v4();
    await _storage.write(key: _kDeviceId, value: _deviceId);
    await _storage.write(key: _kPrivate, value: _private!.d!.toRadixString(16));
  }

  /// Forget this phone's key (e.g. after the admin rejects it). A new key is
  /// created on next use and must be registered again.
  Future<void> reset() async {
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kPrivate);
    _private = null;
    _public = null;
    _deviceId = null;
  }

  String get deviceId => _deviceId!;

  /// Base64 of the 65-byte uncompressed public point, as the server expects.
  String get publicKeyBase64 => base64Encode(_public!.Q!.getEncoded(false));

  /// Signs `message` (ECDSA P-256, SHA-256, deterministic k). Returns base64 of r||s.
  String sign(Uint8List message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_private!));
    final sig = signer.generateSignature(message) as ECSignature;
    return base64Encode(Uint8List.fromList(_fixed32(sig.r) + _fixed32(sig.s)));
  }

  static List<int> _fixed32(BigInt v) {
    final out = List<int>.filled(32, 0);
    var x = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  /// A stable per-phone ID used to stop one phone serving two scholars:
  /// ANDROID_ID on Android, identifierForVendor on iOS.
  static Future<String> hardwareId() async {
    if (Platform.isAndroid) {
      return (await const AndroidId().getId()) ?? 'android-unknown';
    }
    final ios = await DeviceInfoPlugin().iosInfo;
    return ios.identifierForVendor ?? 'ios-unknown';
  }

  static Future<String> model() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return '${a.manufacturer} ${a.model}';
    }
    final i = await info.iosInfo;
    return i.utsname.machine;
  }
}
