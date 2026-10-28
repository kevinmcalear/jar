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

func evaluateUnlock() async -> LAContext? {
    let context = LAContext()
    // Reuse this success for the keychain read. A second evaluatePolicy, or a biometry-protected item with no context, prompts again.
    context.touchIDAuthenticationAllowableReuseDuration = 10
    guard deviceCanUnlock() else { return context }
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return nil }
    guard (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Jar")) == true else { return nil }
    return context
}

func saveHouseholdKey(_ key: SymmetricKey, context: LAContext? = nil) throws {
    let data = key.withUnsafeBytes { Data($0) }
    var delete = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.kevinmcalear.jar", kSecAttrAccount: "household-key"] as [String: Any]
    if let context { delete[kSecUseAuthenticationContext as String] = context }
    SecItemDelete(delete as CFDictionary)
    var insert = delete
    insert.removeValue(forKey: kSecUseAuthenticationContext as String)
    insert[kSecValueData as String] = data
    insert[kSecAttrSynchronizable as String] = false
    // ponytail: AfterFirstUnlock and no Face ID on the item. A silent push has to decrypt while the phone is locked. The screen still asks for Face ID. Put biometry back only if background notices go away.
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(insert as CFDictionary, nil)
    if status != errSecSuccess { throw KeychainError.unreadable }
    UserDefaults.standard.set(true, forKey: "jar.keyAfterFirstUnlock")
}

func deleteHouseholdKey() {
    let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.kevinmcalear.jar", kSecAttrAccount: "household-key"] as [String: Any]
    SecItemDelete(query as CFDictionary)
}

func readHouseholdKey(context: LAContext? = nil) -> SymmetricKey? {
    var query = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.kevinmcalear.jar",
        kSecAttrAccount: "household-key",
        kSecReturnData: true,
        kSecAttrSynchronizable: false,
    ] as [String: Any]
    if let context { query[kSecUseAuthenticationContext as String] = context }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else { return nil }
    return SymmetricKey(data: data)
}

