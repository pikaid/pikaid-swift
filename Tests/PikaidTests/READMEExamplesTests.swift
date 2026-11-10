import Foundation
import Pikaid
import Testing

/// Executes the usage examples published in `README.md`.
///
/// Every snippet that documents a public entrypoint is reproduced here with
/// the documented literal values and expected output. This suite exists so the
/// README cannot drift from the shipped API: CI runs it through the public
/// module only (`import Pikaid`, not `@testable`).
@Suite("README examples")
struct READMEExamplesTests {
  @Test("Generate example")
  func generate() throws {
    let id = try Pikaid.generate()
    #expect(id.string.count == 26)
    #expect(id.timestamp > 0)
    #expect(id.randomnessHex.count == 24)
  }

  @Test("Documented sample identifier")
  func documentedSample() throws {
    let id = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
    #expect(id.timestamp == 1_700_000_000)
    #expect(id.string == "0s44we8002loz3po6mcf6vsn23")
  }

  @Test("Timestamp generation examples")
  func timestampGeneration() throws {
    let fixed = try Pikaid.generate(timestamp: 1_700_000_000)
    #expect(fixed.timestamp == 1_700_000_000)

    let bytes = try Pikaid.generateBinary()
    #expect(bytes.count == 17)

    let fixedBytes = try Pikaid.generateBinary(timestamp: 1_700_000_000)
    #expect(fixedBytes.count == 17)
    #expect(try Pikaid(binary: fixedBytes).timestamp == 1_700_000_000)
  }

  @Test("Parse and convert example")
  func parseAndConvert() throws {
    let fromString = try Pikaid(string: "zzzzzzz7oiylpimjg5u2ca1ypr")
    let fromBinary = try Pikaid(binary: fromString.binary)  // Data, 17 bytes
    let fromBytes = try Pikaid(binary: fromString.binaryBytes)

    let rebuilt = try Pikaid(
      timestamp: fromString.timestamp,
      randomness: fromString.randomness
    )

    #expect(fromString == fromBinary)
    #expect(fromString == fromBytes)
    #expect(fromString == rebuilt)
    #expect(fromString.description == fromString.string)
    #expect(fromString.binary.count == 17)
    #expect(fromString.randomness.count == 12)
  }

  @Test("Validate example")
  func validate() {
    #expect(Pikaid.isValid("0s44we8002loz3po6mcf6vsn23"))
    #expect(!Pikaid.isValid("000000A0000000000000000000"))
    #expect(!Pikaid.isValid("0000000zzzzzzzzzzzzzzzzzzz"))

    #expect(Pikaid.isWellFormed("0000000zzzzzzzzzzzzzzzzzzz"))
  }

  @Test("Strict failure example")
  func strictFailure() {
    do {
      _ = try Pikaid(string: "0000000000000000000000000")  // 25 characters
      Issue.record("25-character string must not parse")
    } catch let error as PikaidError {
      #expect(error.errorDescription != nil)
      #expect(error == .invalidStringLength(actual: 25, expected: 26))
    } catch {
      Issue.record("unexpected error type: \(error)")
    }
  }

  @Test("Codable example")
  func codable() throws {
    let sample = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
    let data = try JSONEncoder().encode(sample)
    #expect(String(decoding: data, as: UTF8.self) == "\"0s44we8002loz3po6mcf6vsn23\"")
    let decoded = try JSONDecoder().decode(Pikaid.self, from: data)
    #expect(decoded == sample)
  }

  @Test("API summary constants match the documentation")
  func apiSummaryConstants() {
    #expect(Pikaid.maximumTimestamp == 78_364_164_095)
    #expect(Pikaid.stringLength == 26)
    #expect(Pikaid.binaryLength == 17)
    #expect(Pikaid.timestampCharacterCount == 7)
    #expect(Pikaid.randomnessCharacterCount == 19)
    #expect(Pikaid.randomnessByteCount == 12)
  }

  @Test("Comparison documentation holds for the parsed sample")
  func comparison() throws {
    let low = try Pikaid(string: "00000000000000000000000000")
    let high = try Pikaid(string: "00000000000000000000000001")
    let nextSecond = try Pikaid(string: "00000010000000000000000000")

    #expect(low < high)
    #expect(high < nextSecond)
    #expect(low.string < high.string)
    #expect(low.binaryBytes.lexicographicallyPrecedes(high.binaryBytes))
  }
}
