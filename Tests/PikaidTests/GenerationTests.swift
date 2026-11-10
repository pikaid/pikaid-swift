import Foundation
import Testing

@testable import Pikaid

@Suite("Secure generation")
struct GenerationTests {
  @Test("generate() uses the current time and produces a valid identifier")
  func generateUsesCurrentTime() throws {
    let before = Int64(Date().timeIntervalSince1970)
    let id = try Pikaid.generate()
    let after = Int64(Date().timeIntervalSince1970)

    #expect(id.string.count == 26)
    #expect(Pikaid.isValid(id.string))
    #expect(Pikaid.isWellFormed(id.string))
    #expect(id.binary.count == 17)
    #expect(id.randomness.count == 12)
    #expect(id.timestamp >= before)
    #expect(id.timestamp <= after)
    #expect(try Pikaid(string: id.string) == id)
  }

  @Test("generate(timestamp:) honours the supplied timestamp")
  func generateWithExplicitTimestamp() throws {
    for timestamp: Int64 in [0, 1, 1_700_000_000, 4_294_967_296, Pikaid.maximumTimestamp] {
      let id = try Pikaid.generate(timestamp: timestamp)
      #expect(id.timestamp == timestamp)
      #expect(Pikaid.isValid(id.string))
      #expect(id.string.count == 26)
      #expect(id.randomness.count == 12)
    }
  }

  @Test("generate(timestamp:) rejects invalid timestamps")
  func generateRejectsInvalidTimestamps() {
    for timestamp: Int64 in [-1, Pikaid.maximumTimestamp + 1, Int64.max, Int64.min] {
      #expect(throws: PikaidError.invalidTimestamp(timestamp)) {
        try Pikaid.generate(timestamp: timestamp)
      }
    }
  }

  @Test("Binary generation variants agree with the string form")
  func generateBinaryVariants() throws {
    let binary = try Pikaid.generateBinary(timestamp: 1_234_567_890)
    #expect(binary.count == 17)
    #expect(try Pikaid(binary: binary).timestamp == 1_234_567_890)
    #expect(try Pikaid(binary: binary).binary == binary)

    let now = try Pikaid.generateBinary()
    #expect(now.count == 17)
    #expect(try Pikaid(binary: now).string.count == 26)
  }

  @Test("Binary generation rejects invalid timestamps")
  func generateBinaryRejectsInvalidTimestamps() {
    #expect(throws: PikaidError.invalidTimestamp(-1)) {
      try Pikaid.generateBinary(timestamp: -1)
    }
  }

  @Test("Cryptographic failure fails closed")
  func cryptographicFailureFailsClosed() {
    #expect(throws: PikaidError.randomnessUnavailable) {
      try Pikaid.generate(timestamp: 1, using: FailingRandomnessSource())
    }
  }

  @Test("A randomness source returning the wrong length is rejected")
  func randomnessSourceWrongLengthIsRejected() {
    for count in [0, 1, 11, 13, 32] {
      let source = WrongLengthRandomnessSource(
        bytes: [UInt8](repeating: 0x9D, count: count)
      )
      #expect(throws: PikaidError.invalidRandomnessLength(actual: count, expected: 12)) {
        try Pikaid.generate(timestamp: 1, using: source)
      }
    }
  }

  @Test("Timestamps are validated before randomness is requested")
  func timestampsAreCheckedBeforeRandomness() {
    // The source would fail, but the deterministic timestamp error wins.
    #expect(throws: PikaidError.invalidTimestamp(-1)) {
      try Pikaid.generate(timestamp: -1, using: FailingRandomnessSource())
    }
  }

  @Test("Injected entropy is used verbatim")
  func injectedEntropyIsUsedVerbatim() throws {
    let entropy = TestHex.bytes("00112233445566778899aabb")
    let id = try Pikaid.generate(
      timestamp: 1_700_000_000,
      using: StaticRandomnessSource(bytes: entropy)
    )
    #expect(id.timestamp == 1_700_000_000)
    #expect(id.randomnessHex == "00112233445566778899aabb")
    #expect(id.string == "0s44we8002loz3po6mcf6vsn23")
  }

  @Test("Successive generations do not repeat")
  func successiveGenerationsDoNotRepeat() throws {
    var seen = Set<String>()
    for _ in 0..<64 {
      let id = try Pikaid.generate()
      #expect(seen.insert(id.string).inserted, "duplicate pikaid generated")
    }
  }

  @Test("Generated entropy is not constant or zero")
  func generatedEntropyIsNotConstant() throws {
    var entropies = Set<String>()
    for _ in 0..<32 {
      entropies.insert(try Pikaid.generate().randomnessHex)
    }
    #expect(entropies.count > 1)
    #expect(try Pikaid.generate().randomness != [UInt8](repeating: 0, count: 12))
  }

  @Test("Generated strings use only lowercase Base36")
  func generatedStringsAreLowercaseBase36() throws {
    let alphabet = Set("0123456789abcdefghijklmnopqrstuvwxyz")
    for _ in 0..<32 {
      let id = try Pikaid.generate()
      #expect(id.string.allSatisfy { alphabet.contains($0) })
    }
  }
}
