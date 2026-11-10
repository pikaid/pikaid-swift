import Foundation

/// A validated, immutable pikaid identifier.
///
/// A pikaid is exactly 26 lowercase Base36 characters: a seven-character
/// whole-second Unix timestamp followed by a nineteen-character encoding of
/// 96 bits of cryptographic randomness. Its binary representation is exactly
/// 17 bytes: a five-byte big-endian timestamp followed by the twelve original
/// randomness bytes.
///
/// Every instance is valid by construction. Use ``init(string:)``, one of the
/// binary initializers, or ``generate()`` to create one; invalid input throws a
/// ``PikaidError`` rather than being truncated or normalized.
///
/// ```swift
/// let id = try Pikaid.generate()
/// let text = id.string              // 26 characters
/// let bytes = id.binary             // 17 bytes
/// let parsed = try Pikaid(string: text)
/// let same = try Pikaid(binary: bytes)
/// #expect(parsed == same)
/// ```
///
/// - Important: pikaid is not a secret, authentication token, or authorization
///   mechanism. Randomness reduces accidental collisions but does not guarantee
///   uniqueness. Values generated in the same second are ordered by their random
///   suffix, not by generation order, and the timestamp has one-second
///   precision.
public struct Pikaid: Sendable, Hashable, Comparable, CustomStringConvertible {
  /// The length of the canonical string form: 26 ASCII characters.
  public static let stringLength = 26

  /// The length of the binary form: 17 bytes.
  public static let binaryLength = 17

  /// The number of characters occupied by the timestamp: 7.
  public static let timestampCharacterCount = 7

  /// The number of characters occupied by the randomness suffix: 19.
  public static let randomnessCharacterCount = 19

  /// The number of randomness bytes: 12 (96 bits).
  public static let randomnessByteCount = 12

  /// The largest valid timestamp, `36^7 - 1` (`78_364_164_095`).
  public static let maximumTimestamp: Int64 = 78_364_164_095

  /// The whole-second Unix timestamp encoded in the identifier.
  public let timestamp: Int64

  /// The original twelve randomness bytes, including leading zeros.
  public let randomness: [UInt8]

  // MARK: - Creation

  /// Parses a canonical pikaid string with full semantic validation.
  ///
  /// The input must contain exactly 26 UTF-8 bytes from `[0-9a-z]`. Uppercase
  /// letters, separators, whitespace, non-ASCII input, invalid lengths, and
  /// randomness suffixes larger than 96 bits are rejected.
  ///
  /// - Parameter string: The candidate identifier.
  /// - Throws: ``PikaidError`` when the input is not a valid pikaid.
  public init(string: String) throws {
    let bytes = Array(string.utf8)
    guard bytes.count == Self.stringLength else {
      throw PikaidError.invalidStringLength(actual: bytes.count, expected: Self.stringLength)
    }

    var timestamp: UInt64 = 0
    var randomness = [UInt8](repeating: 0, count: Self.randomnessByteCount)

    for index in bytes.indices {
      guard let digit = Base36.digitValue(of: bytes[index]) else {
        throw PikaidError.invalidCharacter(byte: bytes[index], index: index)
      }

      if index < Self.timestampCharacterCount {
        timestamp = timestamp * 36 + UInt64(digit)
      } else {
        var carry = Int(digit)
        for byteIndex in stride(from: randomness.count - 1, through: 0, by: -1) {
          let product = Int(randomness[byteIndex]) * 36 + carry
          randomness[byteIndex] = UInt8(product & 0xFF)
          carry = product >> 8
        }
        guard carry == 0 else {
          throw PikaidError.randomnessOverflow
        }
      }
    }

    guard timestamp <= UInt64(Self.maximumTimestamp) else {
      throw PikaidError.timestampOverflow(timestamp)
    }
    self.init(validatedTimestamp: Int64(timestamp), randomness: randomness)
  }

  /// Parses the 17-byte binary representation with full validation.
  ///
  /// - Parameter data: Exactly 17 bytes in the canonical binary layout.
  /// - Throws: ``PikaidError`` for an invalid length or a timestamp above
  ///   ``maximumTimestamp``.
  public init(binary data: Data) throws {
    try self.init(binary: [UInt8](data))
  }

  /// Parses the 17-byte binary representation with full validation.
  ///
  /// - Parameter bytes: Exactly 17 bytes in the canonical binary layout.
  /// - Throws: ``PikaidError`` for an invalid length or a timestamp above
  ///   ``maximumTimestamp``.
  public init(binary bytes: [UInt8]) throws {
    guard bytes.count == Self.binaryLength else {
      throw PikaidError.invalidBinaryLength(actual: bytes.count, expected: Self.binaryLength)
    }

    var timestamp: UInt64 = 0
    for index in 0..<5 {
      timestamp = (timestamp << 8) | UInt64(bytes[index])
    }
    guard timestamp <= UInt64(Self.maximumTimestamp) else {
      throw PikaidError.timestampOverflow(timestamp)
    }

    self.init(
      validatedTimestamp: Int64(timestamp),
      randomness: Array(bytes[5..<Self.binaryLength])
    )
  }

  /// Creates a pikaid from validated components.
  ///
  /// This initializer is useful when importing known timestamp and randomness
  /// values. Callers are responsible for the quality of supplied randomness;
  /// production identifiers should normally be created with ``generate()``.
  ///
  /// - Parameters:
  ///   - timestamp: A non-negative Unix timestamp up to `36^7 - 1`.
  ///   - randomness: Exactly twelve randomness bytes.
  /// - Throws: ``PikaidError`` for an out-of-range timestamp or an invalid
  ///   randomness length.
  public init(timestamp: Int64, randomness: [UInt8]) throws {
    guard timestamp >= 0, timestamp <= Self.maximumTimestamp else {
      throw PikaidError.invalidTimestamp(timestamp)
    }
    guard randomness.count == Self.randomnessByteCount else {
      throw PikaidError.invalidRandomnessLength(
        actual: randomness.count,
        expected: Self.randomnessByteCount
      )
    }
    self.init(validatedTimestamp: timestamp, randomness: randomness)
  }

  /// Creates a pikaid from validated components.
  ///
  /// - Parameters:
  ///   - timestamp: A non-negative Unix timestamp up to `36^7 - 1`.
  ///   - randomness: Exactly twelve randomness bytes.
  /// - Throws: ``PikaidError`` for an out-of-range timestamp or an invalid
  ///   randomness length.
  public init(timestamp: Int64, randomness: Data) throws {
    try self.init(timestamp: timestamp, randomness: [UInt8](randomness))
  }

  private init(validatedTimestamp: Int64, randomness: [UInt8]) {
    self.timestamp = validatedTimestamp
    self.randomness = randomness
  }

  // MARK: - Generation

  /// Generates a pikaid from the current UTC time and 96 bits of CSPRNG data.
  ///
  /// - Throws: ``PikaidError`` when the system clock is outside the valid
  ///   timestamp range or the cryptographic source fails.
  public static func generate() throws -> Pikaid {
    try generate(timestamp: currentTimestamp())
  }

  /// Generates a pikaid with an explicitly supplied timestamp.
  ///
  /// The timestamp is still range-checked, and the randomness suffix still
  /// comes from the platform CSPRNG.
  ///
  /// - Parameter timestamp: Whole seconds since the Unix epoch.
  /// - Throws: ``PikaidError`` for an invalid timestamp or cryptographic
  ///   failure.
  public static func generate(timestamp: Int64) throws -> Pikaid {
    try generate(timestamp: timestamp, using: SystemRandomnessSource())
  }

  internal static func generate(
    timestamp: Int64,
    using source: some RandomnessSource
  ) throws -> Pikaid {
    guard timestamp >= 0, timestamp <= maximumTimestamp else {
      throw PikaidError.invalidTimestamp(timestamp)
    }

    let randomness: [UInt8]
    do {
      randomness = try source.randomBytes(count: randomnessByteCount)
    } catch {
      throw PikaidError.randomnessUnavailable
    }
    guard randomness.count == randomnessByteCount else {
      throw PikaidError.invalidRandomnessLength(
        actual: randomness.count,
        expected: randomnessByteCount
      )
    }

    return try Pikaid(timestamp: timestamp, randomness: randomness)
  }

  /// Generates a pikaid directly in its 17-byte binary representation.
  ///
  /// - Throws: ``PikaidError`` when the system clock is outside the valid
  ///   timestamp range or the cryptographic source fails.
  public static func generateBinary() throws -> Data {
    try generate().binary
  }

  /// Generates a binary pikaid with an explicitly supplied timestamp.
  ///
  /// - Parameter timestamp: Whole seconds since the Unix epoch.
  /// - Throws: ``PikaidError`` for an invalid timestamp or cryptographic
  ///   failure.
  public static func generateBinary(timestamp: Int64) throws -> Data {
    try generate(timestamp: timestamp).binary
  }

  private static func currentTimestamp() -> Int64 {
    Int64(Date().timeIntervalSince1970.rounded(.down))
  }

  // MARK: - Validation

  /// Returns whether a string is a fully valid pikaid.
  ///
  /// This performs length, alphabet, timestamp, and 96-bit randomness
  /// validation. It returns `false` instead of throwing.
  ///
  /// - Parameter string: The candidate identifier.
  public static func isValid(_ string: String) -> Bool {
    (try? Pikaid(string: string)) != nil
  }

  /// Returns whether a string has the pikaid shape.
  ///
  /// This checks only that the input is exactly 26 ASCII bytes from
  /// `[0-9a-z]`. It deliberately does **not** check whether the randomness
  /// suffix fits in 96 bits, so a `true` result does not mean the value is a
  /// valid pikaid. Use ``isValid(_:)`` for full validation.
  ///
  /// - Parameter string: The candidate identifier.
  public static func isWellFormed(_ string: String) -> Bool {
    let bytes = Array(string.utf8)
    guard bytes.count == Self.stringLength else {
      return false
    }
    return bytes.allSatisfy { Base36.digitValue(of: $0) != nil }
  }

  // MARK: - Representations

  /// The canonical 26-character lowercase Base36 string.
  public var string: String {
    var bytes = Base36.encodeTimestamp(timestamp)
    bytes.append(contentsOf: Base36.encodeRandomness(randomness))
    return String(decoding: bytes, as: UTF8.self)
  }

  /// The canonical 17-byte binary representation.
  public var binary: Data {
    Data(binaryBytes)
  }

  /// The canonical 17-byte binary representation as a byte array.
  public var binaryBytes: [UInt8] {
    var bytes = [UInt8](repeating: 0, count: Self.binaryLength)
    let value = UInt64(timestamp)
    for index in 0..<5 {
      let shift = UInt64(8 * (4 - index))
      bytes[index] = UInt8((value >> shift) & 0xFF)
    }
    for index in 0..<Self.randomnessByteCount {
      bytes[5 + index] = randomness[index]
    }
    return bytes
  }

  /// The twelve randomness bytes as 24 lowercase hexadecimal characters.
  public var randomnessHex: String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(Self.randomnessByteCount * 2)
    for byte in randomness {
      bytes.append(Base36.hexDigits[Int(byte >> 4)])
      bytes.append(Base36.hexDigits[Int(byte & 0x0F)])
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  /// The canonical string form.
  public var description: String {
    string
  }

  // MARK: - Comparison

  /// Orders pikaids by timestamp and then by unsigned randomness.
  ///
  /// Different timestamps sort chronologically. Within one second, the random
  /// suffix decides order; identifiers are not ordered by generation time.
  /// This order is identical to ASCII-compatible comparison of the canonical
  /// strings and to unsigned bytewise comparison of the binary forms.
  public static func < (lhs: Pikaid, rhs: Pikaid) -> Bool {
    if lhs.timestamp != rhs.timestamp {
      return lhs.timestamp < rhs.timestamp
    }
    return lhs.randomness.lexicographicallyPrecedes(rhs.randomness)
  }
}

extension Pikaid: Codable {
  /// Decodes a pikaid from its canonical string representation.
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    do {
      try self.init(string: string)
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid pikaid: \(error)"
      )
    }
  }

  /// Encodes the pikaid as its canonical string representation.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(string)
  }
}
