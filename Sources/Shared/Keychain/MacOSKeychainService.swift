// WP-19 · macOS Keychain 真实实现（v15.18 · Stage A 用于 SQLCipher passphrase）
//
// 设计取舍：
// - Security framework SecItemAdd / SecItemCopyMatching / SecItemDelete
// - service 标识固定为 bundleIdentifier（默认 "FuturesTerminal"）· 跨 App 独立命名空间
// - kSecAttrAccessible = afterFirstUnlockThisDeviceOnly · 解锁后可读 + 不跟随 iCloud 同步
// - actor 串行 · SecItem* 系列虽线程安全但避免 race · 单一 actor 入口
// - 失败 OSStatus → 翻译为 KeychainError（itemNotFound / duplicateItem / ioFailed）

#if canImport(Security)

import Foundation
import Security

public actor MacOSKeychainService: KeychainService {

    private let service: String

    public init(service: String = "FuturesTerminal") {
        self.service = service
    }

    public func read(key: String) async throws -> Data {
        var query = baseQuery(account: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.ioFailed("Keychain 返回非 Data 类型")
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.ioFailed("OSStatus=\(status)")
        }
    }

    public func write(key: String, data: Data) async throws {
        // 先尝试更新 · 不存在再 add（avoid duplicateItem 异常路径成主流）
        let updateQuery = baseQuery(account: key)
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // fall through to add
            break
        default:
            throw KeychainError.ioFailed("update OSStatus=\(updateStatus)")
        }

        var addQuery = baseQuery(account: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            throw KeychainError.duplicateItem
        default:
            throw KeychainError.ioFailed("add OSStatus=\(addStatus)")
        }
    }

    public func delete(key: String) async throws {
        let query = baseQuery(account: key)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return  // idempotent
        default:
            throw KeychainError.ioFailed("delete OSStatus=\(status)")
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account
        ]
    }
}

#endif
