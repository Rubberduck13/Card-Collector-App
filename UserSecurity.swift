import Foundation
import CryptoKit
import Security
import LocalAuthentication

// MARK: - User Model

public struct UserAccount: Codable, Equatable {
    public let username: String
    public let email: String
    public let passwordSalt: Data
    public let passwordHash: Data

    public init(
        username: String,
        email: String,
        passwordSalt: Data,
        passwordHash: Data
    ) {
        self.username = username
        self.email = email
        self.passwordSalt = passwordSalt
        self.passwordHash = passwordHash
    }
}

// MARK: - Errors

public enum UserSecurityError: Error {
    case invalidCredentials
    case duplicateAccount
    case accountNotFound
    case biometricUnavailable
    case biometricFailed
    case encodingFailed
    case decodingFailed
    case keychainError(OSStatus)
}

// MARK: - User Security

public final class UserSecurity {

    private let service = "com.example.CardGradingApp"
    private let accountKey = "registeredUser"

    public init() {}

    // MARK: Registration

    @discardableResult
    public func register(
        username: String,
        email: String,
        password: String
    ) throws -> UserAccount {

        if try loadUser() != nil {
            throw UserSecurityError.duplicateAccount
        }

        let salt = randomSalt(length: 32)
        let hash = hashPassword(password, salt: salt)

        let user = UserAccount(
            username: username,
            email: email,
            passwordSalt: salt,
            passwordHash: hash
        )

        try saveUser(user)

        return user
    }

    // MARK: Login

    public func login(
        email: String,
        password: String
    ) throws -> UserAccount {

        guard let user = try loadUser() else {
            throw UserSecurityError.accountNotFound
        }

        guard user.email.caseInsensitiveCompare(email) == .orderedSame else {
            throw UserSecurityError.invalidCredentials
        }

        let candidateHash = hashPassword(password, salt: user.passwordSalt)

        guard constantTimeEqual(candidateHash, user.passwordHash) else {
            throw UserSecurityError.invalidCredentials
        }

        return user
    }

    // MARK: Face ID / Touch ID

    public func authenticateWithBiometrics(
        reason: String = "Unlock your card portfolio"
    ) async throws {

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {
            throw UserSecurityError.biometricUnavailable
        }

        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )

        guard success else {
            throw UserSecurityError.biometricFailed
        }
    }

    // MARK: Keychain

    private func saveUser(_ user: UserAccount) throws {

        let encoder = JSONEncoder()

        guard let data = try? encoder.encode(user) else {
            throw UserSecurityError.encodingFailed
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]

        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw UserSecurityError.keychainError(status)
        }
    }

    public func loadUser() throws -> UserAccount? {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?

        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw UserSecurityError.keychainError(status)
        }

        guard
            let data = result as? Data,
            let user = try? JSONDecoder().decode(UserAccount.self, from: data)
        else {
            throw UserSecurityError.decodingFailed
        }

        return user
    }

    public func deleteUser() throws {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UserSecurityError.keychainError(status)
        }
    }

    // MARK: Password Hashing

    private func hashPassword(
        _ password: String,
        salt: Data
    ) -> Data {

        var input = Data(password.utf8)
        input.append(salt)

        let digest = SHA256.hash(data: input)

        return Data(digest)
    }

    private func randomSalt(length: Int) -> Data {

        var bytes = [UInt8](repeating: 0, count: length)

        _ = SecRandomCopyBytes(
            kSecRandomDefault,
            length,
            &bytes
        )

        return Data(bytes)
    }

    private func constantTimeEqual(
        _ lhs: Data,
        _ rhs: Data
    ) -> Bool {

        guard lhs.count == rhs.count else {
            return false
        }

        var difference: UInt8 = 0

        for (a, b) in zip(lhs, rhs) {
            difference |= a ^ b
        }

        return difference == 0
    }
}
