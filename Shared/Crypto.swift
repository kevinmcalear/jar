import Foundation
import CryptoKit
import CommonCrypto

enum FieldCryptoError: Error {
    case seal
}

let householdVerifier = Data("daily-jar".utf8)

func deriveHouseholdKey(passphrase: String, salt: Data, iterations: Int = 600_000) -> SymmetricKey {
    let password = Array(passphrase.utf8)
    let saltBytes = Array(salt)
    var derived = [UInt8](repeating: 0, count: 32)
    let status = CCKeyDerivationPBKDF(
        CCPBKDFAlgorithm(kCCPBKDF2),
        password,
        password.count,
        saltBytes,
        saltBytes.count,
        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
        UInt32(iterations),
        &derived,
        derived.count
    )
    if status != kCCSuccess {
        fatalError("PBKDF2 failed")
    }
    return SymmetricKey(data: Data(derived))
}

func sealField(_ plaintext: Data, record: String, field: String, key: SymmetricKey) throws -> Data {
    let box = try AES.GCM.seal(plaintext, using: key, authenticating: associated(record, field))
    guard let combined = box.combined else { throw FieldCryptoError.seal }
    return combined
}

func openField(_ sealed: Data, record: String, field: String, key: SymmetricKey) throws -> Data {
    let box = try AES.GCM.SealedBox(combined: sealed)
    return try AES.GCM.open(box, using: key, authenticating: associated(record, field))
}

func centsPlaintext(_ cents: Int) -> Data {
    var big = Int64(cents).bigEndian
    return Data(bytes: &big, count: MemoryLayout<Int64>.size)
}

func cents(from data: Data) -> Int? {
    guard data.count == MemoryLayout<Int64>.size else { return nil }
    let raw = data.withUnsafeBytes { $0.load(as: Int64.self) }
    return Int(Int64(bigEndian: raw))
}

private func associated(_ record: String, _ field: String) -> Data {
    // Record name plus field name, split by "|", so a blob cannot be pasted onto another record or field.
    Data("\(record)|\(field)".utf8)
}
