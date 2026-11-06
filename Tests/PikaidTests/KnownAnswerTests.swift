import Foundation
import Testing

@testable import Pikaid

/// Known-answer cases computed by an independent Python oracle, not by the Swift
/// implementation under test. Every expected string, binary value, and boundary
/// result here can be reproduced with plain integer Base36 arithmetic.
@Suite("Independent known answers")
struct KnownAnswerTests {
  struct Case {
    let name: String
    let timestamp: Int64
    let entropyHex: String
    let id: String
    let binHex: String
  }

  static let cases: [Case] = [
    Case(
      name: "timestamp-36^2-1-with-zero-entropy",
      timestamp: 1_295,
      entropyHex: "000000000000000000000000",
      id: "00000zz0000000000000000000",
      binHex: "000000050f000000000000000000000000"
    ),
    Case(
      name: "timestamp-36^2-with-zero-entropy",
      timestamp: 1_296,
      entropyHex: "000000000000000000000000",
      id: "00001000000000000000000000",
      binHex: "0000000510000000000000000000000000"
    ),
    Case(
      name: "maximum-timestamp-with-zero-entropy",
      timestamp: 78_364_164_095,
      entropyHex: "000000000000000000000000",
      id: "zzzzzzz0000000000000000000",
      binHex: "123ede3fff000000000000000000000000"
    ),
    Case(
      name: "timestamp-2^32-with-zero-entropy",
      timestamp: 4_294_967_296,
      entropyHex: "000000000000000000000000",
      id: "1z141z40000000000000000000",
      binHex: "0100000000000000000000000000000000"
    ),
    Case(
      name: "zero-timestamp-entropy-1",
      timestamp: 0,
      entropyHex: "000000000000000000000001",
      id: "00000000000000000000000001",
      binHex: "0000000000000000000000000000000001"
    ),
    Case(
      name: "zero-timestamp-entropy-2^95",
      timestamp: 0,
      entropyHex: "800000000000000000000000",
      id: "00000003u9haurb9q2x1650zcw",
      binHex: "0000000000800000000000000000000000"
    ),
    Case(
      name: "zero-timestamp-maximum-entropy",
      timestamp: 0,
      entropyHex: "ffffffffffffffffffffffff",
      id: "00000007oiylpimjg5u2ca1ypr",
      binHex: "0000000000ffffffffffffffffffffffff"
    ),
    Case(
      name: "zero-timestamp-truncated-32-bit-entropy",
      timestamp: 0,
      entropyHex: "0000000000000000deadbeef",
      id: "00000000000000000001ps9wxb",
      binHex: "00000000000000000000000000deadbeef"
    ),
    Case(
      name: "timestamp-1-maximum-entropy",
      timestamp: 1,
      entropyHex: "ffffffffffffffffffffffff",
      id: "00000017oiylpimjg5u2ca1ypr",
      binHex: "0000000001ffffffffffffffffffffffff"
    ),
  ]

  @Test("Oracle cases round-trip through every representation")
  func oracleCasesRoundTripEveryRepresentation() throws {
    for testCase in Self.cases {
      let fromString = try Pikaid(string: testCase.id)
      #expect(fromString.timestamp == testCase.timestamp, "\(testCase.name)")
      #expect(fromString.randomnessHex == testCase.entropyHex, "\(testCase.name)")
      #expect(fromString.string == testCase.id, "\(testCase.name)")
      #expect(TestHex.string(fromString.binary) == testCase.binHex, "\(testCase.name)")

      let fromBinary = try Pikaid(binary: TestHex.bytes(testCase.binHex))
      #expect(fromBinary == fromString, "\(testCase.name)")
      #expect(fromBinary.string == testCase.id, "\(testCase.name)")

      let fromComponents = try Pikaid(
        timestamp: testCase.timestamp,
        randomness: TestHex.bytes(testCase.entropyHex)
      )
      #expect(fromComponents == fromString, "\(testCase.name)")
      #expect(TestHex.string(fromComponents.binary) == testCase.binHex, "\(testCase.name)")
    }
  }

  @Test("Entropy overflow begins immediately above 2^96 - 1")
  func entropyOverflowBoundary() throws {
    // 2^96 - 1 is the largest representable 96-bit randomness value.
    let maximum = try Pikaid(string: "00000007oiylpimjg5u2ca1ypr")
    #expect(maximum.randomnessHex == "ffffffffffffffffffffffff")

    // 2^96 padded to nineteen Base36 digits is the first overflow value.
    #expect(throws: PikaidError.randomnessOverflow) {
      try Pikaid(string: "00000007oiylpimjg5u2ca1yps")
    }

    // 36^19 - 1 is larger still and must also overflow.
    #expect(throws: PikaidError.randomnessOverflow) {
      try Pikaid(string: "0000000zzzzzzzzzzzzzzzzzzz")
    }

    // The shape check deliberately accepts overflow-shaped strings.
    #expect(Pikaid.isWellFormed("00000007oiylpimjg5u2ca1yps"))
    #expect(!Pikaid.isValid("00000007oiylpimjg5u2ca1yps"))
  }

  @Test("Timestamp overflow is bounded by 36^7 - 1")
  func timestampOverflowBoundary() throws {
    let maximum = try Pikaid(string: "zzzzzzz0000000000000000000")
    #expect(maximum.timestamp == Pikaid.maximumTimestamp)

    // No seven-digit Base36 string can exceed 36^7 - 1, so the only
    // timestamp overflow path is the binary representation.
    #expect(throws: PikaidError.timestampOverflow(78_364_164_096)) {
      try Pikaid(binary: TestHex.bytes("123ede4000000000000000000000000000"))
    }
    #expect(throws: PikaidError.timestampOverflow(1_099_511_627_775)) {
      try Pikaid(binary: TestHex.bytes("ffffffffff000000000000000000000000"))
    }
  }

  @Test("Fixed-width padding is mandatory")
  func fixedWidthPaddingIsMandatory() {
    // Equivalent values with stripped leading zeroes are not canonical.
    #expect(!Pikaid.isValid("0000000001"))
    #expect(!Pikaid.isValid("000000000000000000001"))
    #expect(!Pikaid.isValid("000000000000000000000001"))
  }
}
