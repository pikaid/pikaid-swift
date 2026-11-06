import Foundation

#if canImport(Security)
  import Security
#endif

/// A source of cryptographic randomness used by pikaid generation.
///
/// The protocol is internal so that callers cannot accidentally substitute a
/// weak generator in production. Tests use it to exercise failure handling.
protocol RandomnessSource: Sendable {
  func randomBytes(count: Int) throws -> [UInt8]
}

/// The default platform cryptographic randomness source.
struct SystemRandomnessSource: RandomnessSource {
  func randomBytes(count: Int) throws -> [UInt8] {
    precondition(count >= 0)
    guard count > 0 else {
      return []
    }

    var bytes = [UInt8](repeating: 0, count: count)

    #if canImport(Security)
      let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
        guard let baseAddress = buffer.baseAddress else {
          return errSecParam
        }
        return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
      }
      guard status == errSecSuccess else {
        throw PikaidError.randomnessUnavailable
      }
      return bytes
    #else
      // Swift's system generator is backed by the platform CSPRNG
      // (for example getrandom(2) on Linux). It never falls back to a
      // non-cryptographic generator.
      var generator = SystemRandomNumberGenerator()
      var offset = 0
      while offset < count {
        var value = generator.next()
        withUnsafeBytes(of: &value) { rawBuffer in
          let amount = min(rawBuffer.count, count - offset)
          for index in 0..<amount {
            bytes[offset + index] = rawBuffer[index]
          }
          offset += amount
        }
      }
      return bytes
    #endif
  }
}
