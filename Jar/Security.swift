import Foundation
import CryptoKit
import LocalAuthentication
import Security

enum KeychainError: Error {
    case unreadable
}

func randomSalt() -> Data {
    var bytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes)
}

func deviceCanUnlock() -> Bool {
    var error: NSError?
    return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
}

func evaluateUnlock() async -> Bool {
    let context = LAContext()
    var error: NSError?
    let reason = "Unlock Jar"
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
        if let ok = try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason), ok {
            return true
        }
    }
    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
        if let ok = try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason), ok {
            return true
        }
    }
    // ponytail: a simulator or a device with no passcode cannot satisfy Face ID. The key stays on this device only until a passcode exists.
    return !deviceCanUnlock()
}

func saveHouseholdKey(_ key: SymmetricKey) throws {
    let data = key.withUnsafeBytes { Data($0) }
    let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.kevinmcalear.jar", kSecAttrAccount: "household-key"] as [String: Any]
    SecItemDelete(query as CFDictionary)
    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrSynchronizable as String] = false
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    if let access = keyAccess() {
        insert[kSecAttrAccessControl as String] = access
        insert.removeValue(forKey: kSecAttrAccessible as String)
    }
    let status = SecItemAdd(insert as CFDictionary, nil)
    if status != errSecSuccess { throw KeychainError.unreadable }
}

func readHouseholdKey() -> SymmetricKey? {
    let query = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.kevinmcalear.jar",
        kSecAttrAccount: "household-key",
        kSecReturnData: true,
        kSecAttrSynchronizable: false,
    ] as [String: Any]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else { return nil }
    return SymmetricKey(data: data)
}

private func keyAccess() -> SecAccessControl? {
    guard deviceCanUnlock() else { return nil }
    return SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet, .or, .devicePasscode], nil)
}
