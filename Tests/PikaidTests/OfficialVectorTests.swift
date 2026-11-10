import Foundation
import Testing

@testable import Pikaid

/// Executes the official pikaid PHP v1.2.0 interoperability vectors.
///
/// The fixture is copied verbatim from
/// `pikaid/pikaid-php@e3f843e/tests/vectors/pikaid-v1.json` and is treated as an
/// independent interoperability oracle, never as an API template.
@Suite("Official interoperability vectors")
struct OfficialVectorTests {
  private let vectors: PikaidVectorFile

  init() throws {
    vectors = try PikaidVectors.load()
  }

  @Test("Fixture metadata matches the pinned specification")
  func metadataMatchesSpecification() {
    let meta = vectors.meta
    #expect(meta.project == "pikaid")
    #expect(meta.stringLength == Pikaid.stringLength)
    #expect(meta.stringLength == 26)
    #expect(meta.timestamp.encoding == "base36-lower")
    #expect(meta.timestamp.chars == Pikaid.timestampCharacterCount)
    #expect(meta.timestamp.min == 0)
    #expect(meta.timestamp.max == Pikaid.maximumTimestamp)
    #expect(meta.entropy.bytes == Pikaid.randomnessByteCount)
    #expect(meta.entropy.chars == Pikaid.randomnessCharacterCount)
    #expect(meta.entropy.encoding == "base36-lower")
    #expect(meta.binary.bytes == Pikaid.binaryLength)
    #expect(meta.specRevision == "1.0.4")
    #expect(meta.identifierFormat.contains("unversioned"))
    #expect(vectors.valid.count == 4)
    #expect(vectors.invalid.string.count == 6)
    #expect(vectors.invalid.binary.count == 4)
  }

  @Test("Every official valid vector round-trips through all representations")
  func allOfficialValidVectors() throws {
    for vector in vectors.valid {
      let parsed = try Pikaid(string: vector.id)

      #expect(parsed.timestamp == vector.timestamp, "\(vector.name)")
      #expect(TestHex.string(parsed.randomness) == vector.entropyHex, "\(vector.name)")
      #expect(parsed.randomnessHex == vector.entropyHex, "\(vector.name)")
      #expect(parsed.string == vector.id, "\(vector.name)")
      #expect(TestHex.string(parsed.binary) == vector.binHex, "\(vector.name)")
      #expect(parsed.binary.count == 17, "\(vector.name)")
      #expect(Pikaid.isValid(vector.id), "\(vector.name)")
      #expect(Pikaid.isWellFormed(vector.id), "\(vector.name)")

      let fromBinary = try Pikaid(binary: TestHex.bytes(vector.binHex))
      #expect(fromBinary == parsed, "\(vector.name)")
      #expect(fromBinary.string == vector.id, "\(vector.name)")

      let fromData = try Pikaid(binary: Data(TestHex.bytes(vector.binHex)))
      #expect(fromData == parsed, "\(vector.name)")

      let fromComponents = try Pikaid(
        timestamp: vector.timestamp,
        randomness: TestHex.bytes(vector.entropyHex)
      )
      #expect(fromComponents == parsed, "\(vector.name)")
      #expect(fromComponents.string == vector.id, "\(vector.name)")
    }
  }

  @Test("Every official invalid string vector is rejected")
  func allOfficialInvalidStringVectors() throws {
    for vector in vectors.invalid.string {
      #expect(!Pikaid.isValid(vector.id), "\(vector.name) must fail full validation")
      let expected = try #require(Self.expectedStringError(named: vector.name))
      #expect(throws: expected) {
        try Pikaid(string: vector.id)
      }
    }
  }

  @Test("Every official invalid binary vector is rejected")
  func allOfficialInvalidBinaryVectors() throws {
    for vector in vectors.invalid.binary {
      let bytes = TestHex.bytes(vector.binHex)
      let expected = try #require(Self.expectedBinaryError(named: vector.name))
      #expect(throws: expected) {
        try Pikaid(binary: bytes)
      }
    }
  }

  @Test("Uppercase input is rejected rather than lowercased")
  func uppercaseIsNotCoerced() {
    let uppercase = "000000A0000000000000000000"
    #expect(!Pikaid.isValid(uppercase))
    #expect(!Pikaid.isWellFormed(uppercase))
    // A coercion-based implementation would accept `lowercased()`; pikaid must not.
    #expect(Pikaid.isValid(uppercase.lowercased()))
    #expect(throws: PikaidError.invalidCharacter(byte: 0x41, index: 6)) {
      try Pikaid(string: uppercase)
    }
  }

  private static func expectedStringError(named name: String) -> PikaidError? {
    switch name {
    case "too-short":
      return .invalidStringLength(actual: 25, expected: 26)
    case "too-long":
      return .invalidStringLength(actual: 27, expected: 26)
    case "uppercase":
      return .invalidCharacter(byte: 0x41, index: 6)
    case "invalid-char-dash":
      return .invalidCharacter(byte: 0x2D, index: 6)
    case "non-base36":
      return .invalidCharacter(byte: 0x5F, index: 6)
    case "entropy-overflow":
      return .randomnessOverflow
    default:
      return nil
    }
  }

  private static func expectedBinaryError(named name: String) -> PikaidError? {
    switch name {
    case "too-short":
      return .invalidBinaryLength(actual: 16, expected: 17)
    case "too-long":
      return .invalidBinaryLength(actual: 18, expected: 17)
    case "timestamp-overflow":
      return .timestampOverflow(78_364_164_096)
    case "timestamp-overflow-max-40-bit":
      return .timestampOverflow(1_099_511_627_775)
    default:
      return nil
    }
  }
}
