import Flutter
import UIKit

private let KEYCHAIN_SERVICE = "flutter_secure_storage_service"
private let CHANNEL_NAME = "api0"

private let InvalidParameters = "Invalid parameter's type"

public class SwiftApi0Plugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "api0", binaryMessenger: registrar.messenger())
        let instance = SwiftApi0Plugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func secOSStatusToString(_ c: OSStatus) -> String {
        let t = SecCopyErrorMessageString(c, nil) as! String
        return t
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments: [String: Any] = call.arguments == nil ? [:] : call.arguments as! [String: Any]
        if "read" == call.method {
            guard let key = arguments["key"] as? String else {
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": "NO_KEY_INPUT_PARAM"]);
            }
            var getQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KEYCHAIN_SERVICE,
                kSecReturnData as String: kCFBooleanTrue,
                kSecAttrAccount as String: key
            ]
            if let groupId = arguments["groupId"] as? String {
                getQuery[kSecAttrAccessGroup as String] = groupId
            }
            var queryResult: AnyObject?
            let status = withUnsafeMutablePointer(to: &queryResult) {
                SecItemCopyMatching(getQuery as CFDictionary, $0)
            }
            guard (status == errSecSuccess) else {
                let b = "SecItemCopyMatching is " + secOSStatusToString(status)
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": b])
            }
            let queryResultAsString: String = String(decoding: queryResult as! Data, as: UTF8.self)
            return result(["resultCode": "OK", "resultData": queryResultAsString, "reasonText": "OK"])
        } else if "delete" == call.method {
            guard let key = arguments["key"] as? String else {
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": "NO_KEY_INPUT_PARAM"]);
            }
            var delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KEYCHAIN_SERVICE,
                kSecAttrAccount as String: key
            ]
            if let groupId = arguments["groupId"] as? String {
                delQuery[kSecAttrAccessGroup as String] = groupId
            }
            let status = SecItemDelete(delQuery as CFDictionary)
            guard (status == errSecSuccess) else {
                let b = "SecItemDelete is " + secOSStatusToString(status)
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": b])
            }
            return result(["resultCode": "OK", "resultData": nil, "reasonText": "OK"])
        } else if "deleteAll" == call.method {
            var delAllQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KEYCHAIN_SERVICE
            ]
            if let groupId = arguments["groupId"] as? String {
                delAllQuery[kSecAttrAccessGroup as String] = groupId
            }
            let status = SecItemDelete(delAllQuery as CFDictionary)
            guard (status == errSecSuccess) else {
                let b = "SecItemDelete is " + secOSStatusToString(status)
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": b])
            }
            return result(["resultCode": "OK", "resultData": nil, "reasonText": "OK"])
        } else if "write" == call.method {
            guard let key = arguments["key"] as? String else {
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": "NO_KEY_INPUT_PARAM"]);
            }
            guard let value: String = arguments["value"] as? String else {
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": "NO_VALUE_INPUT_PARAM"]);
            }
            var getQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KEYCHAIN_SERVICE,
                kSecAttrAccount as String: key,
                kSecMatchLimit as String: kSecMatchLimitOne,
                // kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            if let groupId = arguments["groupId"] as? String {
                getQuery[kSecAttrAccessGroup as String] = groupId
            }
            let status1 = SecItemCopyMatching(getQuery as CFDictionary, nil)
            if (status1 == errSecSuccess) {
                let attrUpdate: [String: Any] = [kSecValueData as String: value.data(using: .utf8, allowLossyConversion: false)]
                getQuery.removeValue(forKey: kSecMatchLimit as String)
                let status2 = SecItemUpdate(getQuery as CFDictionary, attrUpdate as CFDictionary)
                guard (status2 == errSecSuccess) else {
                    let b = "SecItemUpdate is " + secOSStatusToString(status2)
                    return result(["resultCode": "FAIL", "resultData": nil, "reasonText": b])
                }
                return result(["resultCode": "OK", "resultData": nil, "reasonText": "OK"])
            }
            getQuery.removeValue(forKey: kSecMatchLimit as String)
            getQuery[kSecValueData as String] = value.data(using: .utf8, allowLossyConversion: false)
            let status3 = SecItemAdd(getQuery as CFDictionary, nil)
            guard status3 == errSecSuccess else {
                let b = "SecItemAdd is " + secOSStatusToString(status3)
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": b])
            }
            return result(["resultCode": "OK", "resultData": nil, "reasonText": "OK"])
        } else if "readAll" == call.method {
            var getQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: KEYCHAIN_SERVICE,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnData as String: kCFBooleanTrue,
                kSecReturnAttributes as String: kCFBooleanTrue
            ]
            if let groupId = arguments["groupId"] as? String {
                getQuery[kSecAttrAccessGroup as String] = groupId
            }
            var queryResult: AnyObject?
            let status1 = withUnsafeMutablePointer(to: &queryResult) {
                SecItemCopyMatching(getQuery as CFDictionary, $0)
            }
            guard (status1 == errSecSuccess) else {
                let b = "SecItemCopyMatching is " + secOSStatusToString(status1)
                return result(["resultCode": "OK", "resultData": nil, "reasonText": b])
            }
            guard let queryResultAsArray = queryResult as? [[String: Any]] else {
                return result(["resultCode": "FAIL", "resultData": nil, "reasonText": "queryResult is null"])
            }
            var r: [String: String] = [:]
            for item in queryResultAsArray {
                let k: String = item[kSecAttrAccount as String] as! String
                let v = item[kSecValueData as String]
                r[k] = String(decoding: v as! Data, as: UTF8.self)
            }
            return result(["resultCode": "OK", "resultData": r, "reasonText": "OK"])
        } else if "getPlatformVersion" == call.method {
            return result(["resultCode": "OK", "resultData": "iOS " + UIDevice.current.systemVersion, "reasonText": "OK"])
        }
        return result(FlutterMethodNotImplemented)
    }
}
