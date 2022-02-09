import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:api0/api0_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:dio_http_cache/dio_http_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http_parser/http_parser.dart';

import 'cryptography/cryptography.dart' as cryptography;
import 'utils.dart';
import 'package:http/http.dart' as http;

// Definition:
// A:  this client
// B:  the server

enum API0Method { post, get, del, put }

class Api0 {
  static bool isDevelopment = false;
  static bool logDioRequestResponse = false;
  static int counterApiRequestIndex = 0;
  static DioCacheManager? _dioCacheManager;

  static const MethodChannel _channel = const MethodChannel('api0');

  static Future<dynamic> _channelInvokeMethod(
      String cmd, dynamic arguments) async {
    return _channel.invokeMethod(cmd, arguments).then((value) {
      if (value["resultCode"] != "OK") {
        String m = value["reasonText"];
        print("_channelInvokeMethod = ($m) <= $cmd: $arguments");
        // throw Exception(cmd + ":" + m);
        return null;
      }
      return value["resultData"];
    });
  }

  static Future<String?> platformVersion() async {
    final String? version =
        await _channelInvokeMethod('getPlatformVersion', null);
    return version;
  }

  static Future<bool> secureStorageWrite(
      {required String key, required String? value}) async {
    final bool? r = await _channelInvokeMethod(
        'write', <String, dynamic>{'key': key, 'value': value});
    if (r == null) return false;
    return r;
  }

  static Future<String?> secureStorageRead(
      {required String key,
      API0IOSOptions? iOptions,
      API0AndroidOptions? aOptions}) async {
    final String? value = await _channelInvokeMethod('read', <String, dynamic>{
      'key': key,
      'options': _selectOptions(iOptions, aOptions)
    });
    return value;
  }

  static Future<bool> secureStorageContainsKey(
      {required String key,
      API0IOSOptions? iOptions,
      API0AndroidOptions? aOptions}) async {
    try {
      String? value = await secureStorageRead(
          key: key, iOptions: iOptions, aOptions: aOptions);
      return value != null;
    } catch (e) {
      return false;
    }
  }

  static Future<void> secureStorageDelete(
          {required String key,
          API0IOSOptions? iOptions,
          API0AndroidOptions? aOptions}) =>
      _channelInvokeMethod('delete', <String, dynamic>{
        'key': key,
        'options': _selectOptions(iOptions, aOptions)
      });

  static Future<Map<String, dynamic>?> secureStorageReadAll(
      {API0IOSOptions? iOptions, API0AndroidOptions? aOptions}) async {
    final Map? results = await _channelInvokeMethod('readAll',
        <String, dynamic>{'options': _selectOptions(iOptions, aOptions)});
    if (results == null) return null;
    var r = Map<String, dynamic>();
    results.forEach((key, value) {
      r[key] = value;
    });
    return r;
  }

  static Future<void> secureStorageDeleteAll(
          {API0IOSOptions? iOptions, API0AndroidOptions? aOptions}) =>
      _channelInvokeMethod('deleteAll',
          <String, dynamic>{'options': _selectOptions(iOptions, aOptions)});

  static Map<String, String>? _selectOptions(
      API0IOSOptions? iOptions, API0AndroidOptions? aOptions) {
    if (kIsWeb) return null;
    return Platform.isIOS ? iOptions?.params : aOptions?.params;
  }

  static Map config = {
    'BE': "",
    'type': 1,
    'flavor': 'PRODUCTION',
    'clientDeviceId': 'device-0001',
    'url': 'http://localhost',
    'url_step_1': '/01',
    'url_step_2': '/02',
    'fingerprints': [
      'b6b9a6af3e866cbe0e6a307e7dda173b372b2d3ac3f06af15f97718773848008',
      '9aed33c4b87ed95ada957b9d62d7e1f0c2ef9b4d9a8c50954a8a03d6a0f05419'
    ]
  };

  static OnBadCertificate? onBadCertificate;
  static OnNoInternetConnection? onNoInternetConnection;

  static Future<void> checkInternetConnection() async {
    if (kIsWeb) return;
    try {
      Uri u = Uri.parse(config['url']);
      final result = await InternetAddress.lookup(u.host);
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return;
      }
    } on SocketException catch (_) {
      if (onNoInternetConnection != null) {
        onNoInternetConnection!();
      } else {
        throw Exception('NO_INTERNET_CONNECTION');
      }
    }
  }

  static Dio createHttpClientSession() {
    Dio dioSession = Dio();
    dioSession.options.connectTimeout = 60000;
    dioSession.options.receiveTimeout = 60000;
    if (isDevelopment) {
      if (logDioRequestResponse) {
        dioSession.interceptors.add(LogInterceptor(
          responseBody: true,
          error: true,
          requestHeader: true,
          responseHeader: true,
          request: true,
          requestBody: true,
        ));
      }
    }
    dioSession.httpClientAdapter = DefaultHttpClientAdapter();
    if (kIsWeb) return dioSession;

    (dioSession.httpClientAdapter as DefaultHttpClientAdapter)
        .onHttpClientCreate = (client) {
      SecurityContext sc = new SecurityContext(withTrustedRoots: true);
      HttpClient httpClient = new HttpClient(context: sc);
      httpClient.maxConnectionsPerHost = 5;
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        Digest certificateDigest = sha256.convert(cert.der);
        for (var fingerprint in config['fingerprints']) {
          if (fingerprint.toLowerCase() == certificateDigest.toString()) {
            return true;
          }
        }
        if (onBadCertificate != null) onBadCertificate!(cert, host, port);
        return false;
      };
      return httpClient;
    };

    return dioSession;
  }

  static void clearAllCache() {
    _dioCacheManager!.clearAll();
  }

  static Future<API0Response> _unprotectedApi(
    API0Method method,
    String url,
    String paramsAsString, {
    Map<String, String>? headers,
    Duration? durationCache,
  }) async {
    try {
      String baseUrl =
          config["url"].toString().replaceAll('apiproxy', 'api/v1/');
      String fullUrl = '$baseUrl$url';
      _dioCacheManager = DioCacheManager((CacheConfig(baseUrl: baseUrl)));
      Dio dioSession = createHttpClientSession();
      if (config['flavor'] != 'PRODUCTION') {
        dioSession.interceptors.add(Api0Logger());
      }
      if (durationCache != null) {
        dioSession.interceptors.add(_dioCacheManager!.interceptor);
      }
      late Response r1;
      switch (method) {
        case API0Method.del:
          r1 = await dioSession.delete(fullUrl,
              data: paramsAsString, options: Options(headers: headers));
          break;
        case API0Method.put:
          r1 = await dioSession.put(
            fullUrl,
            data: paramsAsString,
            options: buildCacheOptions(
              durationCache ?? Duration.zero,
              options: Options(headers: headers),
            ),
          );
          break;
        case API0Method.post:
          r1 = await dioSession.post(
            fullUrl,
            data: paramsAsString,
            options: buildCacheOptions(
              durationCache ?? Duration.zero,
              options: Options(headers: headers),
            ),
          );
          break;
        case API0Method.get:
          r1 = await dioSession.get(
            fullUrl,
            options: buildCacheOptions(
              durationCache ?? Duration.zero,
              options: Options(headers: headers),
            ),
          );
          break;
        default:
          throw Exception("API0Method not implemented");
      }
      if ((r1.statusCode! < 200) || (r1.statusCode! > 299)) {
        return API0Response.asError(
            statusCode: r1.statusCode.toString(),
            reasonCode: r1.statusCode.toString(),
            messageText: r1.statusMessage ?? "ERROR-NO_STATUS_MESSAGE");
      }
      if (r1.data is Map) {
        return API0Response.ok(
            statusCode: r1.statusCode.toString(),
            data:
                // r1.data["response_code"] == null
                //     ? jsonEncode(r1.data["body"]):
                r1.data,
            headers: r1.headers.map);
      } else {
        if (r1.data is String) {
          return API0Response.ok(
              statusCode: r1.statusCode.toString(),
              responseMessage: r1.data,
              data: {},
              headers: r1.headers.map);
        } else {
          return API0Response.ok(
              statusCode: r1.statusCode.toString(),
              rawData: r1.data,
              data: {},
              headers: r1.headers.map);
        }
      }
    } on DioError catch (e) {
      return API0Response.asError(
        reasonCode: e.toString(),
        messageText: e.message,
      );
    }
  }

  static Future<API0Response> apiNoProxy(
      API0Method method, String url, Map<String, dynamic>? params,
      {Map<String, String>? headers}) async {
    // if (headers == null) {
    //   headers = {
    //     "Content-Type": "application/json",
    //     "Host": "mgiro-hf.posindonesia.co.id:3443",
    //     "Accept": "*/*",
    //     "Accept-Encoding": "gzip, deflate, br",
    //     "Connection": "keep-alive",
    //   };
    // }
    if (!kReleaseMode) {
      log('${DateTime.now().toString()} =>> API 0 ENCRYPT');
    }
    // final newParams = signParams(params);
    // String encryptedParam =
    //     await EncryptionHelper.encryptPospayProd(jsonEncode(newParams));
    if (!kReleaseMode) {
      log('${DateTime.now().toString()} =>> API 0 RES ENCRYPT');
    }
    // =============== WITHOUT APIPROXY ====================
    var start = DateTime.now();
    String allUrl = "${Api0.config['apiUrl']}$url";

    Uri myUri = Uri.parse(allUrl);
    if (!kReleaseMode) {
      log('${DateTime.now().toString()} =>> API 0 URL : $myUri');
    }
    var response;
    if (!kReleaseMode) {
      log('${DateTime.now().toString()} =>> API 0 ${method.toString()}');
    }
    try {
      switch (method) {
        case API0Method.post:
          response = await http.post(myUri,
              headers: headers, body: jsonEncode(params));
          // print(response.body);
          break;
        case API0Method.get:
          response = await http.get(myUri, headers: headers);
          // print(response.body);
          break;
        default:
          return API0Response.asError(
            statusCode: 'NO METHODS FOUND',
            reasonCode: 'FAILED TO GET REQUESTED METHODS',
            messageText: response.body,
            data: response.body,
          );
      }
      var end = DateTime.now();
      if (!kReleaseMode) {
        log('${DateTime.now().toString()} =>> API 0 RESPONSE $url');
      }
      log('durasi api tanpa apiproxy $url = ' +
          (end.millisecondsSinceEpoch - start.millisecondsSinceEpoch)
              .toString() +
          ' ms');

      if (response == null) {
        return API0Response.asError(
          statusCode: 'UNKNOWN',
          reasonCode: 'FAILED TO GET RESPONSE',
          messageText: "Terjadi kesalahan pada jaringan, silahkan coba lagi",
          data: "Terjadi kesalahan pada jaringan, silahkan coba lagi",
        );
      }

      if (response.statusCode != 200) {
        return API0Response.asError(
          statusCode: 'UNKNOWN',
          reasonCode: 'FAILED TO GET RESPONSE',
          messageText:
              "[${response.statusCode}] Maaf, sedang terjadi kendala pada layanan kami, silahkan coba beberapa saat lagi.",
          data:
              "[${response.statusCode}] Maaf, sedang terjadi kendala pada layanan kami, silahkan coba beberapa saat lagi.",
        );
      }

      if (response.body == null) {
        return API0Response.asError(
          statusCode: 'UNKNOWN',
          reasonCode: 'FAILED TO GET RESPONSE',
          messageText: "Terjadi kesalahan pada jaringan, silahkan coba lagi",
          data: "Terjadi kesalahan pada jaringan, silahkan coba lagi",
        );
      }

      Map<String, dynamic> responseMessageAsJSON = jsonDecode(response.body);
      // Map<String, dynamic> responseMessageAsJSON = json.encode(response.body);
      // try {
      //   responseMessageAsJSON =
      //       await EncryptionHelper.decryptPospayProd(response.body);
      // } catch (e) {
      //   return API0Response.asError(
      //     statusCode: 'UNKNOWN',
      //     reasonCode: 'FAILED DECRYPT POSPAY PROD',
      //     messageText: response.body,
      //     data: response.body,
      //   );
      // }

      if (responseMessageAsJSON['response_code'] != '00') {
        API0Response r = API0Response.asError(
          statusCode: responseMessageAsJSON['response_code'].toString(),
          reasonCode: responseMessageAsJSON['response_code'].toString(),
          messageText: responseMessageAsJSON['response_msg'],
          data: responseMessageAsJSON,
        );
        // printLogResult(apiRequestIndex, r);
        return r;
      }
      API0Response r = API0Response.ok(
          responseMessage: response.body,
          data: responseMessageAsJSON,
          headers: response.headers);
      // printLogResult(apiRequestIndex, r);

      return r;
    } catch (e) {
      if (response == null) {
        return API0Response.asError(
          statusCode: 'UNKNOWN',
          reasonCode: 'FAILED TO GET RESPONSE',
          messageText: "Terjadi kesalahan pada jaringan, silahkan coba lagi",
          data: "Terjadi kesalahan pada jaringan, silahkan coba lagi",
        );
      } else {
        return API0Response.asError(
          statusCode: 'UNKNOWN',
          reasonCode: 'Unknown Error',
          messageText: response.body,
          data: response.body,
        );
      }
    }
  }

  static Future<API0Response> apiJSON(
    API0Method method,
    String url,
    Map<String, dynamic> params, {
    Map<String, String>? headers,
    Duration? durationCache,
  }) async {
    // return apiNoProxy(method, url, params, headers: headers);
    return api(
      method,
      url,
      jsonEncode(params),
      headers: headers,
      durationCache: durationCache,
    );
  }

  static printLogCall(
    int apiRequestIndex,
    int type,
    API0Method method,
    String url,
    String paramsAsString, {
    Map<String, String>? headers,
  }) {
    if (!kReleaseMode) {
      print(
          "\n\n$apiRequestIndex api0.api call: $type, $method, $url\n--Params start--\n$paramsAsString\n--Params end--\n--Headers start--\n"
          "${headers.toString()}\n--Headers end--\n");
    }
  }

  static printLogResult(int apiRequestIndex, API0Response r) {
    if (config['flavor'] != 'PRODUCTION') {
      Api0Logger().printAPI0Response(r);
    }
  }

  static Future<MultipartFile> getMultipartFileImage(File fileImage) async {
    String fileName = fileImage.path.split('/').last;
    String tipe = fileName.split('.').last;
    MultipartFile multipartFile = await MultipartFile.fromFile(
      fileImage.path,
      filename: fileName,
      contentType: MediaType('image', tipe),
    );
    return multipartFile;
  }

  static FormData getFormData(Map<String, dynamic> data) {
    FormData formData = FormData.fromMap(data);
    return formData;
  }

  static bool checkIsParamsEncrypted(String params) {
    bool isParamsEncrypted = false;
    if (params.startsWith('{') &&
        params.endsWith('}') &&
        (params.contains("data") || params.contains('data'))) {
      isParamsEncrypted = true;
    }
    return isParamsEncrypted;
  }

  static Future<API0Response> api(
    API0Method method,
    String url,
    String paramsAsString, {
    Map<String, String>? headers,
    Duration? durationCache,
  }) async {
    assert(isDevelopment = true);
    var apiRequestIndex = counterApiRequestIndex++;
    var t = config['type'];
    bool isParamsEncrypted = checkIsParamsEncrypted(paramsAsString);
    printLogCall(apiRequestIndex, t, method, url, paramsAsString,
        headers: headers);

    try {
      await checkInternetConnection();
      if (!isParamsEncrypted) {
        API0Response r = await _unprotectedApi(
          method,
          url,
          paramsAsString,
          headers: headers,
          durationCache: durationCache,
        );
        return r;
      }
      API0CryptographyAlgorithmBundle c;
      try {
        c = API0CryptographyAlgorithmBundle(t);
      } catch (e) {
        API0Response r =
            API0Response.asError(reasonCode: 'INVALID_REQUEST_CONNECTION_TYPE');
        printLogResult(apiRequestIndex, r);
        return r;
      }

      API0RequestSecurityParam rsp = API0RequestSecurityParam(
          typeIndex: t,
          keyExchangeRequestAKeyPair: await c.keyExchangeAlgorithm.newKeyPair(),
          keyExchangeResponseAKeyPair:
              await c.keyExchangeAlgorithm.newKeyPair(),
          signatureAKeyPair: await c.signatureAlgorithm.newKeyPair());

      switch (method) {
        case API0Method.del:
          url = url + "d";
          break;
        case API0Method.put:
          url = url + "t";
          break;
        case API0Method.post:
          url = url + "p";
          break;
        case API0Method.get:
        default:
          url = url + "g";
          break;
      }
      String url01 = config["url"] + config['url_step_1'];

      Uint8List urlAsBytes = utf8.encode(url) as Uint8List;

      Dio dioSession = createHttpClientSession();
      Uint8List q1StepRequestType =
          vTol32v(Uint8List.fromList([1, config['type']]));
      List<int> q1PackedData = q1StepRequestType +
          vTol32v(rsp.keyExchangeRequestAKeyPair.publicKey.bytes as Uint8List) +
          vTol32v(
              rsp.keyExchangeResponseAKeyPair.publicKey.bytes as Uint8List) +
          vTol32v(rsp.signatureAKeyPair.publicKey.bytes as Uint8List) +
          vTol32v(urlAsBytes);
      Response r1;
      try {
        print('Preparing step 01 for request ' + url01);
        r1 = await dioSession
            .post(url01, data: {'data': base64Encode(q1PackedData)});
        print('Done step 01 for request ' + url01);
      } catch (e) {
        print('Error step 01 ' + e.toString());
        if (e is DioError) {
          if (e.type != DioErrorType.other) {
            if (e.response != null) {
              if (e.response!.statusCode != null) {
                API0Response r = API0Response.asError(
                    statusCode: e.response!.statusCode.toString(),
                    reasonCode: e.response!.statusCode.toString(),
                    messageText:
                        e.response!.statusMessage ?? "ERROR-NO_STATUS_MESSAGE",
                    data: e.response!.data);
                printLogResult(apiRequestIndex, r);
                return r;
              }
            }
          }

          if (e.error != null) {
            if (e.error is String) {
              API0Response r = API0Response.asError(
                  reasonCode: e.error, messageText: e.error);
              printLogResult(apiRequestIndex, r);
              return r;
            }
            if (e.error.osError != null) {
              API0Response r = API0Response.asError(
                  reasonCode: e.error.osError.errorCode.toString(),
                  messageText: e.error.osError.message);
              printLogResult(apiRequestIndex, r);
              return r;
            }
            API0Response r = API0Response.asError(
                reasonCode: e.error.toString(),
                messageText: e.error.toString());
            printLogResult(apiRequestIndex, r);
            return r;
          }
        }
        API0Response r = API0Response.asError(
            reasonCode: e.toString(), messageText: e.toString());
        printLogResult(apiRequestIndex, r);
        return r;
      }

      if (r1.data['code'] == "FAIL") {
        API0Response r = API0Response.asError(
            reasonCode: r1.data['reasonCode'],
            messageText: r1.data['messageText']);
        printLogResult(apiRequestIndex, r);
        return r;
      }
      String r1PackedDataAsBase64String = r1.data['data'];
      Uint8List r1PackedDataAsBytes = base64Decode(r1PackedDataAsBase64String);

      CursorIterator r1Cursor = CursorIterator();
      Uint8List r1SignatureBPublicKey =
          l32vTov(r1PackedDataAsBytes, cursor: r1Cursor);
      Uint8List r1RequestTimeInMsEpochAsBytes =
          l32vTov(r1PackedDataAsBytes, cursor: r1Cursor);
      Uint8List r1RequestBPublicKey =
          l32vTov(r1PackedDataAsBytes, cursor: r1Cursor);
      Uint8List r1ResponseBPublicKey =
          l32vTov(r1PackedDataAsBytes, cursor: r1Cursor);
      Uint8List r1RequestId = l32vTov(r1PackedDataAsBytes, cursor: r1Cursor);

      // int r1RequestTimeInMsEpoch = bytesToUInt64(r1RequestTimeInMsEpochAsBytes);
      // int r1RequestDurationInMs = DateTime.now().millisecondsSinceEpoch - r1RequestTimeInMsEpoch + 2000;
      // if ((0 > r1RequestDurationInMs) || (r1RequestDurationInMs > 5000)) throw Exception('R1_INVALID_TIMESTAMP');

      rsp.requestId = r1RequestId;
      rsp.keyExchangeRequestBPublicKey =
          cryptography.PublicKey(r1RequestBPublicKey);
      rsp.keyExchangeResponseBPublicKey =
          cryptography.PublicKey(r1ResponseBPublicKey);
      rsp.signatureBPublicKey = cryptography.PublicKey(r1SignatureBPublicKey);

      rsp.requestMasterKey = await c.keyExchangeAlgorithm.sharedSecret(
        localPrivateKey: rsp.keyExchangeRequestAKeyPair.privateKey,
        remotePublicKey: rsp.keyExchangeRequestBPublicKey,
      );
      rsp.requestDerivedKey = await c.keyDerivationFunction
          .deriveKey(rsp.requestMasterKey, outputLength: 32);

      rsp.responseMasterKey = await c.keyExchangeAlgorithm.sharedSecret(
        localPrivateKey: rsp.keyExchangeResponseAKeyPair.privateKey,
        remotePublicKey: rsp.keyExchangeResponseBPublicKey,
      );
      rsp.responseDerivedKey = await c.keyDerivationFunction
          .deriveKey(rsp.responseMasterKey, outputLength: 32);

      cryptography.Cipher cipher = c.rq2Cipher;

      Uint8List headerAsBytes = mapToBytes<String, String>(headers);
      rsp.requestNonce = cipher.newNonce()!;
      Uint8List paramsAsBytes = utf8.encode(paramsAsString) as Uint8List;
      List<int> packedParamAsBytes =
          vTol32v(utf8.encode(config['clientDeviceId']) as Uint8List) +
              vTol32v(paramsAsBytes) +
              vTol32v(headerAsBytes);
      Uint8List q2EncryptedRequestMessageAsBytes = await cipher.encrypt(
          packedParamAsBytes,
          secretKey: rsp.requestDerivedKey,
          nonce: rsp.requestNonce);

      int q2EncryptedResponseMessageMaxIndex =
          q2EncryptedRequestMessageAsBytes.length;
      int q2l = q2EncryptedResponseMessageMaxIndex;
      if (q2l > 412) {
        q2l = 412;
      }

      List<int> q2DataToSign = utf8.encode(config['clientDeviceId']) +
          utf8.encode(base64Encode(r1RequestTimeInMsEpochAsBytes)) +
          r1RequestId +
          q2EncryptedRequestMessageAsBytes.sublist(0, q2l) +
          q2EncryptedRequestMessageAsBytes.sublist(
              q2EncryptedResponseMessageMaxIndex - q2l,
              q2EncryptedResponseMessageMaxIndex) +
          rsp.requestNonce.bytes;

      cryptography.Signature q2RequestSignature =
          await c.signatureAlgorithm.sign(q2DataToSign, rsp.signatureAKeyPair);

      String url02 = config["url"] + config['url_step_2'];
      Uint8List q2StepRequestType =
          vTol32v(Uint8List.fromList([2, config['type']]));
      List<int> q2PackedData = q2StepRequestType +
          vTol32v(rsp.requestId) +
          vTol32v(rsp.requestNonce.bytes as Uint8List) +
          vTol32v(q2EncryptedRequestMessageAsBytes) +
          vTol32v(q2RequestSignature.bytes as Uint8List);

      Response r2;
      try {
        String realUrl = url.substring(0, url.length - 1);
        print('Preparing step 02 for request $realUrl');
        r2 = await dioSession
            .post(url02, data: {'data': base64Encode(q2PackedData)});
        print('Done step 02 for request $realUrl');
      } catch (e) {
        print('Error step 02 ' + e.toString());
        if (e is DioError) {
          if (e.type != DioErrorType.other) {
            if (e.response != null) {
              if (e.response!.statusCode != null) {
                API0Response r = API0Response.asError(
                    statusCode: e.response!.statusCode.toString(),
                    reasonCode: e.response!.statusCode.toString(),
                    messageText:
                        e.response!.statusMessage ?? "ERROR-NO_STATUS_MESSAGE",
                    data: e.response!.data);
                printLogResult(apiRequestIndex, r);
                return r;
              }
            }
          }

          if (e.error != null) {
            if (e.error is String) {
              API0Response r = API0Response.asError(
                  reasonCode: e.error, messageText: e.error);
              printLogResult(apiRequestIndex, r);
              return r;
            }
            if (e.error.osError != null) {
              API0Response r = API0Response.asError(
                  reasonCode: e.error.osError.errorCode.toString(),
                  messageText: e.error.osError.message);
              printLogResult(apiRequestIndex, r);
              return r;
            }
            API0Response r = API0Response.asError(
                reasonCode: e.error.toString(),
                messageText: e.error.toString());
            printLogResult(apiRequestIndex, r);
            return r;
          }
        }
        API0Response r = API0Response.asError(
            reasonCode: e.toString(), messageText: e.toString());
        printLogResult(apiRequestIndex, r);
        return r;
      }

      if (r2.statusCode != 200) {
        API0Response r = API0Response.asError(
            reasonCode: r2.statusCode.toString(),
            messageText: r2.statusMessage ?? "ERROR-NO_STATUS_MESSAGE");
        printLogResult(apiRequestIndex, r);
        return r;
      }
      if (r2.data['code'] == 'FAIL') {
        API0Response r = API0Response.asError(
            reasonCode: r2.data['reasonCode'],
            messageText: r2.data['messageText']);
        printLogResult(apiRequestIndex, r);
        return r;
      }
      String r2packedDataAsBase64String = r2.data['data'];
      Uint8List r2packedDataAsBytes = base64Decode(r2packedDataAsBase64String);

      CursorIterator r2Cursor = CursorIterator();
      Uint8List r2RequestId = l32vTov(r2packedDataAsBytes, cursor: r2Cursor);
      l32vTov(r2packedDataAsBytes,
          cursor:
              r2Cursor); // Uint8List r2RequestTimeInMsEpochAsBytes = l32vTov(r2packedDataAsBytes, cursor: r2Cursor);
      Uint8List r2ResponseNonce =
          l32vTov(r2packedDataAsBytes, cursor: r2Cursor);
      Uint8List r2ResponseSignature =
          l32vTov(r2packedDataAsBytes, cursor: r2Cursor);
      Uint8List r2EncryptedResponseMessageAsBytes =
          l32vTov(r2packedDataAsBytes, cursor: r2Cursor);

      // int r2RequestTimeInMsEpoch = bytesToUInt64(r2RequestTimeInMsEpochAsBytes);
      // int r2RequestDuration = DateTime.now().millisecondsSinceEpoch - r2RequestTimeInMsEpoch + 2000;
      // if ((0 > r2RequestDuration) || (r2RequestDuration > 5000)) throw Exception('R2_INVALID_TIMESTAMP');

      // int r2r1DurationInMs = r2RequestTimeInMsEpoch - r1RequestTimeInMsEpoch + 2000;
      // if ((0 > r2r1DurationInMs) || (r2r1DurationInMs > 5000)) throw Exception('R1_R2_INVALID_REQUEST_DURATION');

      rsp.responseNonce = cryptography.Nonce(r2ResponseNonce);

      if (base64Encode(rsp.requestId) != base64Encode(r2RequestId)) {
        throw Exception('R2_INVALID_REQUEST_ID');
      }

      Uint8List r2DecryptedResponseMessageAsBytes = await cipher.decrypt(
          r2EncryptedResponseMessageAsBytes,
          secretKey: rsp.responseDerivedKey,
          nonce: rsp.responseNonce);
      CursorIterator r3Cursor = CursorIterator();
      Uint8List r2ResponseMessageAsBytes =
          l32vTov(r2DecryptedResponseMessageAsBytes, cursor: r3Cursor);
      Uint8List r2ResponseHeaderAsBytes =
          l32vTov(r2DecryptedResponseMessageAsBytes, cursor: r3Cursor);

      Map<String, dynamic> r2ResponseHeader =
          bytesToHashMap(r2ResponseHeaderAsBytes);

      String r2DecryptedResponseMessageAsString =
          utf8.decode(r2ResponseMessageAsBytes, allowMalformed: true);
      Map<String, dynamic> responseMessageAsJSON =
          jsonDecode(r2DecryptedResponseMessageAsString);

      int r2EncryptedResponseMessageMaxIndex =
          r2EncryptedResponseMessageAsBytes.length;
      int l = r2EncryptedResponseMessageMaxIndex;
      if (l > 512) {
        l = 512;
      }
      List<int> r2DataToSign = r2RequestId +
          rsp.requestNonce.bytes +
          r2ResponseNonce +
          r2EncryptedResponseMessageAsBytes.sublist(0, l) +
          r2EncryptedResponseMessageAsBytes.sublist(
              r2EncryptedResponseMessageMaxIndex - l,
              r2EncryptedResponseMessageMaxIndex);

      cryptography.Signature r2CalcSignature = cryptography.Signature(
          r2ResponseSignature,
          publicKey: rsp.signatureBPublicKey);
      bool r2IsVerified =
          await c.signatureAlgorithm.verify(r2DataToSign, r2CalcSignature);
      if (!r2IsVerified) {
        throw Exception("R2_INVALID_SIGNATURE");
      }
      String s = r2DecryptedResponseMessageAsString;
      API0Response r = API0Response.ok(
        responseMessage: s,
        data: responseMessageAsJSON,
        headers: r2ResponseHeader,
      );
      printLogResult(apiRequestIndex, r);
      return r;
    } catch (e) {
      API0Response r = API0Response.asError(
        reasonCode: e.toString(),
        messageText: e.toString(),
      );
      printLogResult(apiRequestIndex, r);
      return r;
    }
  }
}
