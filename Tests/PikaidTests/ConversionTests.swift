import Foundation
import Testing

@testable import Pikaid

@Suite("Lossless conversions")
struct ConversionTests {
  @Test("String to binary to string round-trips")
  func stringBinaryStringRoundTrip() throws {
    let strings = [
      "00000000000000000000000000",
      "zzzzzzz7oiylpimjg5u2ca1ypr",
      "0s44we8002loz3po6mcf6vsn23",
      "00000010000000000000000001",
      "zzzzzzz0000000000000000000",
      "00000007oiylpimjg5u2ca1ypr",
    ]
    for string in strings {
      let id = try Pikaid(string: string)
      let rebuilt = try Pikaid(binary: id.binary)
      #expect(rebuilt == id, "\(string)")
      #expect(rebuilt.string == string)
      #expect(try Pikaid(binary: id.binaryBytes) == id)
      #expect(id.binary.count == Pikaid.binaryLength)
      #expect(id.binaryBytes.count == Pikaid.binaryLength)
    }
  }

  @Test("Binary layout is five timestamp bytes then twelve entropy bytes")
  func binaryLayoutIsTimestampThenRawEntropy() throws {
    let id = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
    #expect(id.timestamp == 1_700_000_000)
    // 1_700_000_000 == 0x006553f100, five big-endian bytes.
    #expect(Array(id.binaryBytes.prefix(5)) == [0x00, 0x65, 0x53, 0xF1, 0x00])
    #expect(Array(id.binaryBytes.suffix(12)) == TestHex.bytes("00112233445566778899aabb"))
    #expect(id.randomnessHex == "00112233445566778899aabb")
  }

  @Test("Leading zeroes are preserved")
  func leadingZeroesArePreserved() throws {
    let id = try Pikaid(timestamp: 0, randomness: TestHex.bytes("000000000000000000000001"))
    #expect(id.string == "00000000000000000000000001")
    #expect(id.binaryBytes.first == 0)
    #expect(id.binaryBytes.last == 1)
    #expect(id.randomnessHex == "000000000000000000000001")

    let maximum = try Pikaid(timestamp: 0, randomness: TestHex.bytes("ffffffffffffffffffffffff"))
    #expect(maximum.string == "00000007oiylpimjg5u2ca1ypr")
    #expect(maximum.randomnessHex == "ffffffffffffffffffffffff")
  }

  @Test("Data and array initializers agree")
  func dataAndArrayInitializersAgree() throws {
    let hex = "00112233445566778899aabb"
    let array = TestHex.bytes(hex)
    let data = Data(array)
    let fromArray = try Pikaid(timestamp: 42, randomness: array)
    let fromData = try Pikaid(timestamp: 42, randomness: data)
    #expect(fromArray == fromData)

    // The full 17-byte form must also agree between `[UInt8]` and `Data`.
    let binaryArray = fromArray.binaryBytes
    let binaryData = Data(binaryArray)
    let binaryFromArray = try Pikaid(binary: binaryArray)
    let binaryFromData = try Pikaid(binary: binaryData)
    #expect(binaryFromArray == binaryFromData)
    #expect(binaryFromArray == fromArray)
    #expect(binaryFromArray.string == binaryFromData.string)
    #expect(binaryFromArray.binary == binaryData)
  }

  @Test("Value semantics protect stored randomness")
  func valueSemanticsProtectStoredRandomness() throws {
    var mutableEntropy = [UInt8](repeating: 0x11, count: 12)
    let id = try Pikaid(timestamp: 1, randomness: mutableEntropy)
    mutableEntropy[0] = 0xFF
    #expect(id.randomness[0] == 0x11)
    #expect(id.randomnessHex == "111111111111111111111111")
  }

  @Test("Description matches the canonical string")
  func descriptionMatchesCanonicalString() throws {
    let id = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
    #expect(id.description == id.string)
    #expect("\(id)" == id.string)
  }

  @Test("Equality and hashing are value based")
  func hashableAndEquatable() throws {
    let a = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
    let b = try Pikaid(binary: a.binary)
    let c = try Pikaid(string: "0s44we8002loz3po6mcf6vsn24")
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
    #expect(a != c)

    let set: Set<Pikaid> = [a, b, c]
    #expect(set.count == 2)
  }

  @Test("Codable uses the canonical string representation")
  func codableUsesCanonicalString() throws {
    let id = try Pikaid(string: "zzzzzzz7oiylpimjg5u2ca1ypr")
    let encoded = try JSONEncoder().encode(id)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"zzzzzzz7oiylpimjg5u2ca1ypr\"")

    let decoded = try JSONDecoder().decode(Pikaid.self, from: encoded)
    #expect(decoded == id)
  }

  @Test("Codable round-trips inside a container")
  func codableRoundTripInsideContainer() throws {
    struct Wrapper: Codable, Equatable {
      let id: Pikaid
      let note: String
    }
    let wrapper = Wrapper(
      id: try Pikaid(string: "00000010000000000000000001"),
      note: "example"
    )
    let data = try JSONEncoder().encode(wrapper)
    let decoded = try JSONDecoder().decode(Wrapper.self, from: data)
    #expect(decoded == wrapper)
  }

  @Test("Codable rejects invalid strings")
  func codableRejectsInvalidStrings() {
    let invalidInputs = [
      "\"\"",
      "\"0000000000000000000000000\"",
      "\"000000A0000000000000000000\"",
      "\"0000000zzzzzzzzzzzzzzzzzzz\"",
      "\"not-a-pikaid\"",
    ]
    for json in invalidInputs {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(Pikaid.self, from: Data(json.utf8))
      }
    }
  }
}
