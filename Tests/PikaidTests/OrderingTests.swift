import Foundation
import Testing

@testable import Pikaid

@Suite("Ordering semantics")
struct OrderingTests {
  @Test("Different seconds sort chronologically regardless of entropy")
  func differentSecondsSortChronologically() throws {
    let early = try Pikaid(
      timestamp: 1_700_000_000,
      randomness: TestHex.bytes("ffffffffffffffffffffffff")
    )
    let late = try Pikaid(
      timestamp: 1_700_000_001,
      randomness: TestHex.bytes("000000000000000000000000")
    )
    #expect(early < late)
    #expect(late > early)
    #expect(early.string < late.string)
    #expect(early.binaryBytes.lexicographicallyPrecedes(late.binaryBytes))
  }

  @Test("Same-second order is unsigned randomness order")
  func sameSecondSortsByUnsignedRandomness() throws {
    // 0x80... would be negative if compared through Int8, so this catches
    // signed-comparison mistakes.
    let low = try Pikaid(timestamp: 10, randomness: TestHex.bytes("000000000000000000000000"))
    let high = try Pikaid(timestamp: 10, randomness: TestHex.bytes("800000000000000000000000"))
    let maximum = try Pikaid(timestamp: 10, randomness: TestHex.bytes("ffffffffffffffffffffffff"))

    #expect(low < high)
    #expect(high < maximum)
    #expect(low < maximum)
    #expect(low.string < high.string)
    #expect(high.string < maximum.string)
  }

  @Test("Comparison matches string and binary order")
  func comparisonMatchesStringAndBinaryOrder() throws {
    let ids = [
      try Pikaid(string: "00000000000000000000000000"),
      try Pikaid(string: "00000000000000000000000001"),
      try Pikaid(string: "0000000000000000000000000z"),
      try Pikaid(string: "00000000000000000000000010"),
      try Pikaid(string: "00000100000000000000000000"),
      try Pikaid(string: "0s44we8002loz3po6mcf6vsn23"),
      try Pikaid(string: "zzzzzzz0000000000000000000"),
      try Pikaid(string: "zzzzzzz7oiylpimjg5u2ca1ypr"),
    ].shuffled()

    let byValue = ids.sorted()
    let byString = ids.sorted { $0.string < $1.string }
    let byBinary = ids.sorted { $0.binaryBytes.lexicographicallyPrecedes($1.binaryBytes) }

    #expect(byValue.map(\.string) == byString.map(\.string))
    #expect(byValue.map(\.string) == byBinary.map(\.string))
    #expect(
      byValue.map(\.string) == [
        "00000000000000000000000000",
        "00000000000000000000000001",
        "0000000000000000000000000z",
        "00000000000000000000000010",
        "00000100000000000000000000",
        "0s44we8002loz3po6mcf6vsn23",
        "zzzzzzz0000000000000000000",
        "zzzzzzz7oiylpimjg5u2ca1ypr",
      ]
    )
  }

  @Test("Equal values are neither less nor greater")
  func equalityIsNeitherLessNorGreater() throws {
    let a = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
    let b = try Pikaid(binary: a.binary)
    #expect(!(a < b))
    #expect(!(b < a))
    #expect(a == b)
  }

  @Test("Timestamp dominates randomness extremes")
  func timestampDominatesRandomnessExtremes() throws {
    let pairs: [(Int64, Int64)] = [
      (0, 1),
      (1_295, 1_296),
      (4_294_967_295, 4_294_967_296),
      (78_364_164_094, 78_364_164_095),
    ]
    for (lower, higher) in pairs {
      let a = try Pikaid(timestamp: lower, randomness: [UInt8](repeating: 0xFF, count: 12))
      let b = try Pikaid(timestamp: higher, randomness: [UInt8](repeating: 0x00, count: 12))
      #expect(a < b, "\(lower) < \(higher)")
      #expect(a.string < b.string, "\(lower) < \(higher)")
    }
  }

  @Test("Ordering is stable under repeated sorting")
  func orderingIsStable() throws {
    let ids = try (0..<50).map { index in
      try Pikaid(
        timestamp: Int64(index % 5),
        randomness: [UInt8](repeating: UInt8(index), count: 12)
      )
    }
    let first = ids.sorted().map(\.string)
    let second = ids.shuffled().sorted().map(\.string)
    #expect(first == second)
  }
}
