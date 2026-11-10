import Foundation
import Testing

@testable import Pikaid

/// Deterministic pseudo-random source for property tests. Not cryptographic and
/// only used to explore the input space.
private struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }

  mutating func nextBytes(_ count: Int) -> [UInt8] {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(count)
    while bytes.count < count {
      var word = next()
      withUnsafeBytes(of: &word) { buffer in
        for index in 0..<min(buffer.count, count - bytes.count) {
          bytes.append(buffer[index])
        }
      }
    }
    return bytes
  }
}

@Suite("Randomized properties")
struct PropertyTests {
  @Test("Random string round-trips preserve every field")
  func randomRoundTripsPreserveEveryField() throws {
    var generator = SplitMix64(seed: 0x5EED_1234_ABCD_0001)
    let alphabet = Set("0123456789abcdefghijklmnopqrstuvwxyz")

    for iteration in 0..<1_000 {
      let timestamp = Int64(generator.next() % (UInt64(Pikaid.maximumTimestamp) + 1))
      let entropy = generator.nextBytes(12)
      let id = try Pikaid(timestamp: timestamp, randomness: entropy)

      #expect(id.string.utf8.count == 26, "iteration \(iteration)")
      #expect(id.binary.count == 17, "iteration \(iteration)")
      #expect(id.randomness.count == 12, "iteration \(iteration)")
      #expect(id.string.allSatisfy { alphabet.contains($0) }, "iteration \(iteration)")
      #expect(try Pikaid(string: id.string) == id, "iteration \(iteration)")
      #expect(try Pikaid(binary: id.binary) == id, "iteration \(iteration)")
      #expect(try Pikaid(binary: id.binaryBytes).string == id.string)
      #expect(try Pikaid(string: id.string).timestamp == timestamp)
      #expect(try Pikaid(string: id.string).randomness == entropy)
      #expect(id.randomnessHex.count == 24)
      #expect(TestHex.bytes(id.randomnessHex) == entropy)
      #expect(Pikaid.isValid(id.string))
    }
  }

  @Test("Random binary round-trips preserve every field")
  func randomBinaryRoundTrips() throws {
    var generator = SplitMix64(seed: 0x0BAD_F00D_0000_0002)
    for iteration in 0..<500 {
      var binary = generator.nextBytes(17)
      // Constrain the leading five bytes to the valid timestamp range.
      let timestamp = UInt64(generator.next() % (UInt64(Pikaid.maximumTimestamp) + 1))
      for index in 0..<5 {
        binary[index] = UInt8((timestamp >> (8 * (4 - index))) & 0xFF)
      }

      let id = try Pikaid(binary: binary)
      #expect(id.timestamp == Int64(timestamp), "iteration \(iteration)")
      #expect(id.binaryBytes == binary, "iteration \(iteration)")
      #expect(try Pikaid(string: id.string).binaryBytes == binary)
      #expect(id.randomness == Array(binary[5...]))
    }
  }

  @Test("Random ordering is consistent across representations")
  func randomOrderingIsConsistent() throws {
    var generator = SplitMix64(seed: 0x0000_0000_0000_0003)
    var ids: [Pikaid] = []
    for _ in 0..<200 {
      let timestamp = Int64(generator.next() % 10_000)
      let entropy = generator.nextBytes(12)
      ids.append(try Pikaid(timestamp: timestamp, randomness: entropy))
    }

    let sortedByValue = ids.sorted().map(\.string)
    let sortedByString = ids.sorted { $0.string < $1.string }.map(\.string)
    let sortedByBinary = ids.sorted {
      $0.binaryBytes.lexicographicallyPrecedes($1.binaryBytes)
    }.map(\.string)

    #expect(sortedByValue == sortedByString)
    #expect(sortedByValue == sortedByBinary)
  }

  @Test("Randomized string mutations are rejected")
  func randomizedMutationsAreRejected() throws {
    var generator = SplitMix64(seed: 0xFEED_FACE_0000_0004)
    let separators: [Character] = ["-", "_", " ", ":", "A", "Z", "/", "!", "~"]

    for _ in 0..<200 {
      let timestamp = Int64(generator.next() % 1_000_000)
      let entropy = generator.nextBytes(12)
      let original = try Pikaid(timestamp: timestamp, randomness: entropy).string

      var characters = Array(original)
      let position = Int(generator.next() % 26)
      let replacement = separators[Int(generator.next() % UInt64(separators.count))]
      characters[position] = replacement
      let mutated = String(characters)

      #expect(!Pikaid.isValid(mutated), "\(mutated)")
      #expect(throws: PikaidError.self) {
        try Pikaid(string: mutated)
      }
    }
  }

  @Test("Random overflow suffixes are rejected")
  func randomOverflowSuffixesAreRejected() {
    var generator = SplitMix64(seed: 0xABCD_0000_0000_0005)
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)
    // Any nineteen Base36 digits starting at '8' or above encode a value
    // >= 8 * 36^18 > 2^96, so all of them must be rejected.
    let leading = Array("89abcdefghijklmnopqrstuvwxyz".utf8)

    for _ in 0..<150 {
      var digits: [UInt8] = []
      digits.reserveCapacity(19)
      digits.append(leading[Int(generator.next() % UInt64(leading.count))])
      for _ in 0..<18 {
        digits.append(alphabet[Int(generator.next() % 36)])
      }
      let suffix = String(decoding: digits, as: UTF8.self)
      let candidate = "0000000" + suffix
      #expect(Pikaid.isWellFormed(candidate))
      #expect(!Pikaid.isValid(candidate), "\(candidate)")
    }
  }

  @Test("Timestamp encoding matches big-endian binary in sampled ranges")
  func timestampEncodingMatchesBinary() throws {
    var generator = SplitMix64(seed: 0x1111_2222_3333_4444)
    let zeroEntropy = [UInt8](repeating: 0, count: 12)
    for _ in 0..<300 {
      // Bias towards boundary regions of the five-byte timestamp.
      let candidates: [Int64] = [
        0,
        1,
        35,
        36,
        Pikaid.maximumTimestamp,
        Pikaid.maximumTimestamp - 1,
        Int64(generator.next() % (UInt64(Pikaid.maximumTimestamp) + 1)),
      ]
      for timestamp in candidates {
        let id = try Pikaid(timestamp: timestamp, randomness: zeroEntropy)
        #expect(id.timestamp == timestamp)
        #expect(try Pikaid(binary: id.binary).timestamp == timestamp)
        #expect(
          TestHex.string(Array(id.binaryBytes.prefix(5))) == Self.fiveByteHex(timestamp)
        )
      }
    }
  }

  private static func fiveByteHex(_ timestamp: Int64) -> String {
    let value = UInt64(timestamp)
    var bytes: [UInt8] = []
    for index in 0..<5 {
      bytes.append(UInt8((value >> (8 * (4 - index))) & 0xFF))
    }
    return TestHex.string(bytes)
  }
}
