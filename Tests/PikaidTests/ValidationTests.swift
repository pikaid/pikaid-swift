import Foundation
import Testing

@testable import Pikaid

@Suite("Strict validation")
struct ValidationTests {
  @Test("String length boundaries are rejected")
  func stringLengthBoundaries() {
    let invalidStrings = [
      "",
      "0",
      "0000000000000000000000000",  // 25
      "000000000000000000000000000",  // 27
      String(repeating: "0", count: 100),
    ]
    for value in invalidStrings {
      #expect(throws: PikaidError.invalidStringLength(actual: value.utf8.count, expected: 26)) {
        try Pikaid(string: value)
      }
      #expect(!Pikaid.isValid(value))
      #expect(!Pikaid.isWellFormed(value))
    }
  }

  @Test("Non-ASCII input is rejected without truncation")
  func nonASCIIInputIsRejected() {
    // 24 ASCII bytes + one two-byte scalar = 26 UTF-8 bytes.
    let value = String(repeating: "0", count: 24) + "é"
    #expect(throws: PikaidError.invalidCharacter(byte: 0xC3, index: 24)) {
      try Pikaid(string: value)
    }

    // A 26-character string that is 27 UTF-8 bytes fails the length gate.
    let wide = String(repeating: "0", count: 25) + "é"
    #expect(wide.count == 26)
    #expect(wide.utf8.count == 27)
    #expect(throws: PikaidError.invalidStringLength(actual: 27, expected: 26)) {
      try Pikaid(string: wide)
    }
  }

  @Test("Uppercase characters are rejected")
  func uppercaseCharactersAreRejected() {
    for scalar in UnicodeScalar("A").value...UnicodeScalar("Z").value {
      var bytes = Array("00000000000000000000000000".utf8)
      bytes[12] = UInt8(scalar)
      let value = String(decoding: bytes, as: UTF8.self)
      #expect(throws: PikaidError.invalidCharacter(byte: UInt8(scalar), index: 12)) {
        try Pikaid(string: value)
      }
      #expect(!Pikaid.isValid(value))
      #expect(!Pikaid.isWellFormed(value))
    }
  }

  @Test("Separators, whitespace and control bytes are rejected")
  func separatorsAndControlBytesAreRejected() {
    let forbidden: [(String, UInt8)] = [
      ("-", 0x2D),
      ("_", 0x5F),
      (" ", 0x20),
      (":", 0x3A),
      (".", 0x2E),
      ("/", 0x2F),
      ("+", 0x2B),
      ("\t", 0x09),
      ("\n", 0x0A),
      ("\0", 0x00),
      ("~", 0x7E),
    ]
    for (character, byte) in forbidden {
      let value = "000000000000" + character + "0000000000000"
      #expect(value.count == 26, "\(character)")
      #expect(throws: PikaidError.invalidCharacter(byte: byte, index: 12)) {
        try Pikaid(string: value)
      }
    }
  }

  @Test("Invalid character indexes are reported accurately")
  func invalidCharacterIndexIsAccurate() {
    #expect(throws: PikaidError.invalidCharacter(byte: 0x41, index: 0)) {
      try Pikaid(string: "A" + String(repeating: "0", count: 25))
    }
    #expect(throws: PikaidError.invalidCharacter(byte: 0x21, index: 25)) {
      try Pikaid(string: String(repeating: "0", count: 25) + "!")
    }
  }

  @Test("Every alphabet byte is accepted in every position")
  func alphabetIsAcceptedEverywhere() throws {
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)
    for byte in alphabet {
      var bytes = Array("00000000000000000000000000".utf8)
      bytes[0] = byte
      bytes[25] = byte
      let value = String(decoding: bytes, as: UTF8.self)
      let parsed = try Pikaid(string: value)
      #expect(parsed.string == value)
    }
  }

  @Test("Shape checking and semantic validation differ")
  func shapeCheckDiffersFromValidation() {
    let overflowing = "00000007oiylpimjg5u2ca1yps"
    #expect(Pikaid.isWellFormed(overflowing))
    #expect(!Pikaid.isValid(overflowing))

    let wellFormed = "0s44we8002loz3po6mcf6vsn23"
    #expect(Pikaid.isWellFormed(wellFormed))
    #expect(Pikaid.isValid(wellFormed))

    #expect(!Pikaid.isWellFormed("0s44we8002loz3po6mcf6vsn2"))
    #expect(!Pikaid.isWellFormed("0s44we8002loz3po6mcf6vsn2!"))
    #expect(!Pikaid.isWellFormed("0S44WE8002LOZ3PO6MCF6VSN23"))
  }

  @Test("Binary length boundaries are rejected")
  func binaryLengthBoundaries() {
    for count in [0, 1, 5, 12, 16, 18, 34] {
      let bytes = [UInt8](repeating: 0, count: count)
      #expect(throws: PikaidError.invalidBinaryLength(actual: count, expected: 17)) {
        try Pikaid(binary: bytes)
      }
      #expect(throws: PikaidError.invalidBinaryLength(actual: count, expected: 17)) {
        try Pikaid(binary: Data(bytes))
      }
    }
  }

  @Test("The maximum binary timestamp is accepted")
  func binaryTimestampMaximumIsAccepted() throws {
    // 0x123ede3fff == 78_364_164_095 == 36^7 - 1.
    let bytes = TestHex.bytes("123ede3fff" + String(repeating: "00", count: 12))
    let id = try Pikaid(binary: bytes)
    #expect(id.timestamp == Pikaid.maximumTimestamp)
    #expect(id.randomness == [UInt8](repeating: 0, count: 12))
    #expect(id.string == "zzzzzzz0000000000000000000")
  }

  @Test("Binary timestamp overflow is rejected")
  func binaryTimestampOverflowIsRejected() {
    #expect(throws: PikaidError.timestampOverflow(78_364_164_096)) {
      try Pikaid(binary: TestHex.bytes("123ede4000" + String(repeating: "00", count: 12)))
    }
    #expect(throws: PikaidError.timestampOverflow(1_099_511_627_775)) {
      try Pikaid(binary: TestHex.bytes("ffffffffff" + String(repeating: "00", count: 12)))
    }
    #expect(throws: PikaidError.timestampOverflow(549_755_813_888)) {
      try Pikaid(binary: TestHex.bytes("8000000000" + String(repeating: "00", count: 12)))
    }
  }

  @Test("Component timestamps are range checked")
  func componentTimestampBoundaries() throws {
    let entropy = [UInt8](repeating: 0, count: 12)

    _ = try Pikaid(timestamp: 0, randomness: entropy)
    _ = try Pikaid(timestamp: Pikaid.maximumTimestamp, randomness: entropy)

    for timestamp in [Int64(-1), Pikaid.maximumTimestamp + 1, Int64.max, Int64.min] {
      #expect(throws: PikaidError.invalidTimestamp(timestamp)) {
        try Pikaid(timestamp: timestamp, randomness: entropy)
      }
    }
  }

  @Test("Component randomness length is enforced")
  func componentRandomnessLengthIsEnforced() {
    for count in [0, 1, 11, 13, 24] {
      let entropy = [UInt8](repeating: 0xAB, count: count)
      #expect(throws: PikaidError.invalidRandomnessLength(actual: count, expected: 12)) {
        try Pikaid(timestamp: 1, randomness: entropy)
      }
      #expect(throws: PikaidError.invalidRandomnessLength(actual: count, expected: 12)) {
        try Pikaid(timestamp: 1, randomness: Data(entropy))
      }
    }
  }

  @Test("Error descriptions are descriptive")
  func errorDescriptionsAreDescriptive() {
    let errors: [PikaidError] = [
      .invalidStringLength(actual: 25, expected: 26),
      .invalidCharacter(byte: 0x41, index: 3),
      .invalidCharacter(byte: 0x00, index: 0),
      .invalidTimestamp(-5),
      .invalidBinaryLength(actual: 16, expected: 17),
      .timestampOverflow(78_364_164_096),
      .randomnessOverflow,
      .invalidRandomnessLength(actual: 11, expected: 12),
      .randomnessUnavailable,
    ]
    for error in errors {
      let description = error.errorDescription
      #expect(description != nil, "\(error)")
      #expect(!(description ?? "").isEmpty, "\(error)")
    }
    #expect(
      (PikaidError.invalidStringLength(actual: 25, expected: 26).errorDescription ?? "")
        .contains("26")
    )
    #expect((PikaidError.randomnessOverflow.errorDescription ?? "").contains("96-bit"))
  }
}
