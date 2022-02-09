import 'dart:async';

// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window;

import 'package:api0/utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// A web implementation of the Api0 plugin.
class Api0Web {
  static void registerWith(Registrar registrar) {
    final MethodChannel channel = MethodChannel(
      'api0',
      const StandardMethodCodec(),
      registrar,
    );

    final pluginInstance = Api0Web();
    channel.setMethodCallHandler(pluginInstance.handleMethodCall);
  }

  /// Handles method calls over the MethodChannel of this plugin.
  /// Note: Check the "federated" architecture for a new way of doing this:
  /// https://flutter.dev/go/federated-plugins
  Future<dynamic> handleMethodCall(MethodCall call) async {
    print('0');
    try {
      switch (call.method) {
        case 'getPlatformVersion':
          String v = await getPlatformVersion();
          return {"resultCode": "OK", "resultData": "Web:" + v, "reasonText": "OK"};
        case 'read':
          String? v = await secureStorageRead(key: call.arguments["key"]);
          return {"resultCode": "OK", "resultData": v, "reasonText": "OK"};
        case 'write':
          bool v = await secureStorageWrite(key: call.arguments["key"], value: call.arguments["value"]);
          return {"resultCode": "OK", "resultData": v, "reasonText": "OK"};
        case 'readAll':
          Map<String, dynamic>? v = await secureStorageReadAll();
          return {"resultCode": "OK", "resultData": v, "reasonText": "OK"};
        case 'deleteAll':
          await secureStorageDeleteAll();
          return {"resultCode": "OK", "resultData": null, "reasonText": "OK"};
        case 'delete':
          await secureStorageDelete(key: call.arguments["key"]);
          return {"resultCode": "OK", "resultData": null, "reasonText": "OK"};
        default:
          throw PlatformException(
            code: 'Unimplemented',
            details: 'api0 for web doesn\'t implement \'${call.method}\'',
          );
      }
    } catch (e) {
      return {"resultCode": "FAIL", "resultData": null, "reasonText": e.toString()};
    }
  }

  /// Returns a [String] containing the version of the platform.
  Future<String> getPlatformVersion() {
    return Future.value(html.window.navigator.userAgent);
  }

  Future<bool> secureStorageWrite({required String key, required String? value}) async {
    if (value == null) {
      html.window.sessionStorage.remove(key);
      return Future.value(true);
    }
    html.window.sessionStorage[key] = value;
    return Future.value(true);
  }

  Future<String?> secureStorageRead({required String key, API0IOSOptions? iOptions, API0AndroidOptions? aOptions}) async {
    return html.window.sessionStorage[key];
  }

  Future<void> secureStorageDelete({required String key, API0IOSOptions? iOptions, API0AndroidOptions? aOptions}) async {
    html.window.sessionStorage.remove(key);
    return;
  }

  Future<Map<String, dynamic>?> secureStorageReadAll({API0IOSOptions? iOptions, API0AndroidOptions? aOptions}) async {
    Map<String, dynamic> r = Map<String, dynamic>();
    html.window.sessionStorage.forEach((key, value) {
      r[key] = value;
    });
    if (r.isEmpty) return null;
    return r;
  }

  Future<void> secureStorageDeleteAll({API0IOSOptions? iOptions, API0AndroidOptions? aOptions}) async {
    html.window.sessionStorage.clear();
    return;
  }
}
