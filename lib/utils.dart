import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cryptography/cryptography.dart' as cryptography;

abstract class API0Options {
  Map<String, String> get params => _toMap();

  Map<String, String> _toMap() {
    throw Exception('Missing implementation');
  }
}

// KeyChain accessibility attributes as defined here:
// https://developer.apple.com/documentation/security/ksecattraccessible?language=objc
enum API0IOSAccessibility {
  // The data in the keychain can only be accessed when the device is unlocked.
  // Only available if a passcode is set on the device.
  // Items with this attribute do not migrate to a new device.
  passcode,

  // The data in the keychain item can be accessed only while the device is unlocked by the user.
  unlocked,

  // The data in the keychain item can be accessed only while the device is unlocked by the user.
  // Items with this attribute do not migrate to a new device.
  unlocked_this_device,

  // The data in the keychain item cannot be accessed after a restart until the device has been unlocked once by the user.
  first_unlock,

  // The data in the keychain item cannot be accessed after a restart until the device has been unlocked once by the user.
  // Items with this attribute do not migrate to a new device.
  first_unlock_this_device,
}

class API0IOSOptions extends API0Options {
  API0IOSOptions(
      {String? groupId,
      API0IOSAccessibility accessibility = API0IOSAccessibility.unlocked})
      : _groupId = groupId,
        _accessibility = accessibility;

  final String? _groupId;
  final API0IOSAccessibility? _accessibility;

  @override
  Map<String, String> _toMap() {
    final m = <String, String>{};
    if (_groupId != null) {
      m['groupId'] = _groupId!;
    }
    if (_accessibility != null) {
      m['accessibility'] = describeEnum(_accessibility!);
    }
    return m;
  }
}

class API0AndroidOptions extends API0Options {
  @override
  Map<String, String> _toMap() {
    return <String, String>{};
  }
}

class API0Error {
  late String code;
  late String statusCode;
  late String? reasonCode;
  late String? messageText;
  late dynamic data;

  void setAllValue({
    required String code,
    required String statusCode,
    String? reasonCode,
    String? messageText,
    dynamic data,
  }) {
    this.code = code;
    this.statusCode = statusCode;
    this.reasonCode = reasonCode;
    if ((messageText == null) && (reasonCode != null)) {
      messageText = reasonCode;
    }
    this.messageText = messageText;
    if (data != null) {
      this.data = data;
    }
  }

  API0Error(
      {String code = 'ERROR',
      String statusCode = 'UNKNOWN',
      String reasonCode = 'UNKNOWN',
      String messageText = 'Unknown error.',
      dynamic data}) {
    this.setAllValue(
        code: code,
        statusCode: statusCode,
        reasonCode: reasonCode,
        messageText: messageText,
        data: data);
  }

  API0Error.ok({String statusCode = "200"}) {
    this.setAllValue(
        code: 'OK',
        statusCode: statusCode,
        reasonCode: 'OK',
        messageText: 'OK');
  }

  String toString() {
    return '{code: "${this.code}", statusCode: "${this.statusCode}", reasonCode: "${this.reasonCode}", messageText: "${this.messageText}"}';
  }
}

enum API0ResponseDataType { error, noData, rawData, string, map }

class API0Response {
  late API0Error error;
  late String? responseMessage;
  Map<dynamic, dynamic> data = {};
  late dynamic rawData;
  late Map<String, dynamic>? headers;
  late API0ResponseDataType dataType;

  API0Response.ok({
    String statusCode = "200",
    String responseMessage = '',
    required Map<dynamic, dynamic> data,
    Map<String, dynamic>? headers,
    dynamic rawData,
  }) {
    this.error = API0Error.ok(statusCode: statusCode);
    this.responseMessage = responseMessage;
    this.data = data;
    this.headers = headers;
    this.rawData = data;
    if (this.data.isNotEmpty) {
      this.dataType = API0ResponseDataType.map;
    } else {
      if (this.responseMessage!.isNotEmpty) {
        this.dataType = API0ResponseDataType.string;
      } else {
        if (this.rawData != null) {
          this.dataType = API0ResponseDataType.rawData;
        } else {
          this.dataType = API0ResponseDataType.noData;
        }
      }
    }
  }

  API0Response.asError({
    String statusCode = "UNKNOWN",
    String reasonCode = "UNKNOWN",
    String messageText = "UNKNOWN",
    dynamic data,
  }) {
    this.error = API0Error(
        statusCode: statusCode,
        reasonCode: reasonCode,
        messageText: messageText,
        data: data);
    this.responseMessage = null;
    this.dataType = API0ResponseDataType.error;
  }

  String toString() {
    return '{error: ${this.error}, response_message: "${this.responseMessage}"}';
  }
}

Map typeCryptographyAlgorithmBundle = {
  0: {'keyExchange': 'secp256k1', 'signature': 'ed25519'},
  1: {'keyExchange': 'X25519', 'signature': 'ed25519'}
};

class API0CryptographyAlgorithmBundle {
  late int typeIndex;
  late cryptography.KeyExchangeAlgorithm keyExchangeAlgorithm;
  late cryptography.SignatureAlgorithm signatureAlgorithm;
  late cryptography.Hkdf keyDerivationFunction;
  late cryptography.Cipher rq2Cipher;

  void setAll(
      int typeIndex,
      cryptography.KeyExchangeAlgorithm keyExchangeAlgorithm,
      cryptography.SignatureAlgorithm signatureAlgorithm) {
    this.typeIndex = typeIndex;
    this.keyExchangeAlgorithm = keyExchangeAlgorithm;
    this.signatureAlgorithm = signatureAlgorithm;
    this.keyDerivationFunction =
        cryptography.Hkdf(cryptography.Hmac(cryptography.sha256));
    this.rq2Cipher = cryptography.CipherWithAppendedMac(
        cryptography.aesCbc, cryptography.Hmac(cryptography.sha256));
  }

  API0CryptographyAlgorithmBundle(typeIndex) {
    switch (typeIndex) {
      case 1:
        {
          setAll(1, cryptography.x25519, cryptography.ed25519);
        }
        break;
      default:
        {
          throw Exception('NOT_IMPLEMENTED');
        }
    }
  }
}

class API0RequestSecurityParam {
  int typeIndex;
  late Uint8List requestId;
  late Uint8List clientDeviceId;
  late cryptography.KeyPair keyExchangeRequestAKeyPair;
  late cryptography.PublicKey keyExchangeRequestBPublicKey;
  late cryptography.KeyPair keyExchangeResponseAKeyPair;
  late cryptography.PublicKey keyExchangeResponseBPublicKey;
  late cryptography.KeyPair signatureAKeyPair;
  late cryptography.PublicKey signatureBPublicKey;
  late cryptography.SecretKey requestMasterKey;
  late cryptography.SecretKey requestDerivedKey;
  late cryptography.Nonce requestNonce;
  late cryptography.SecretKey responseMasterKey;
  late cryptography.SecretKey responseDerivedKey;
  late cryptography.Nonce responseNonce;

  API0RequestSecurityParam(
      {required this.typeIndex,
      required cryptography.KeyPair keyExchangeRequestAKeyPair,
      required cryptography.KeyPair keyExchangeResponseAKeyPair,
      required cryptography.KeyPair signatureAKeyPair}) {
    // this.t = typeIndex;
    this.keyExchangeRequestAKeyPair = keyExchangeRequestAKeyPair;
    this.keyExchangeResponseAKeyPair = keyExchangeResponseAKeyPair;
    this.signatureAKeyPair = signatureAKeyPair;
  }
}

class CursorIterator {
  late int index;

  CursorIterator({int? v}) {
    index = v ?? 0;
  }
}

typedef OnBadCertificate = dynamic Function(
    X509Certificate cert, String host, int port);
typedef OnNoInternetConnection = dynamic Function();

Uint8List int64toBytes(int u) {
  return Uint8List(8)..buffer.asByteData().setInt64(0, u, Endian.little);
}

Uint8List int32toBytes(int u) {
  return Uint8List(4)..buffer.asByteData().setInt32(0, u, Endian.little);
}

int bytesToUInt64(Uint8List u) {
  ByteData x1 = ByteData.sublistView(u);
  var x2 = x1.getUint64(0, Endian.little);
  return x2;
}

int bytesToInt64(Uint8List u) {
  ByteData x1 = ByteData.sublistView(u);
  var x2 = x1.getInt64(0, Endian.little);
  return x2;
}

int bytesToUInt32(Uint8List u, {int startIndex = 0}) {
  ByteData x1 = ByteData.sublistView(u);
  var x2 = x1.getUint32(startIndex, Endian.little);
  return x2;
}

Uint8List vTol32v(Uint8List v) {
  int l = v.lengthInBytes;
  Uint8List t = int32toBytes(l);
  List<int> o = t + v;
  return Uint8List.fromList(o);
}

Uint8List l32vTov(Uint8List l32v, {CursorIterator? cursor}) {
  int startIndex = cursor?.index ?? 0;
  int l = bytesToUInt32(l32v, startIndex: startIndex);
  Uint8List x = l32v.sublist(startIndex + 4, startIndex + 4 + l);
  if (cursor != null) cursor.index = (startIndex + 4 + l);
  return x;
}

Uint8List mapToBytes<K, V>(Map<K, V>? m) {
  if (m == null) return Uint8List(0);
  List<int> r = vTol32v(int64toBytes(m.length));
  m.forEach((K key, V value) {
    r = r + vTol32v(utf8.encode(key.toString()) as Uint8List);
    r = r + vTol32v(utf8.encode(value.toString()) as Uint8List);
  });
  return Uint8List.fromList(r);
}

Map<String, dynamic> bytesToHashMap(Uint8List b) {
  CursorIterator c = CursorIterator();
  Uint8List lAsBytes = l32vTov(b, cursor: c);
  int l = bytesToInt64(lAsBytes);
  Map<String, String> r = HashMap<String, String>();
  for (int i = 0; i < l; i++) {
    Uint8List k = l32vTov(b, cursor: c);
    String key = utf8.decode(k, allowMalformed: true);
    Uint8List v = l32vTov(b, cursor: c);
    String value = utf8.decode(v, allowMalformed: true);
    r[key] = value;
  }
  return r;
}
