import ExpoModulesCore
import Security

public final class LegacyKeychainModule: Module {
  public func definition() -> ModuleDefinition {
    Name("LegacyKeychain")

    AsyncFunction("readLegacySession") { (service: String, account: String) -> String? in
      var query = self.query(service: service, account: account)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
      }
      guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode))
      }
      return value
    }

    AsyncFunction("deleteLegacySession") { (service: String, account: String) -> Bool in
      let status = SecItemDelete(self.query(service: service, account: account) as CFDictionary)
      if status == errSecItemNotFound { return false }
      guard status == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
      }
      return true
    }
  }

  private func query(service: String, account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}
