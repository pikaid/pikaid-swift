import Foundation
import Testing

@testable import Pikaid

/// Executes the pinned, independently generated conformance table.
///
/// The table is produced by `Tests/Conformance/oracle.py`, a pure-Python
/// big-integer reference that never executes the Swift sources. It is pinned to
/// specification revision 1.0.4 and to the official PHP v1.2.0 fixture
/// digests. CI runs `oracle.py --check` before this suite so a mutated table or
/// fixture is rejected before the Swift assertions run.
@Suite("Pinned conformance table")
struct ConformanceTableTests {
  private let table: ConformanceTable

  init() throws {
    table = try ConformanceTable.load()
  }

  @Test("Table metadata pins specification 1.0.4 and official fixture digests")
  func metadata() {
    #expect(table.meta.format == "pikaid-conformance-v1")
    #expect(table.meta.specRevision == "1.0.4")
    #expect(table.meta.specCommit == "17014d76f568c3ac9f9ce2927c1a018fdbc36d1d")
    #expect(
      table.meta.officialFixtureSha256
        == "b0c9dfdd063613424414fef5c9065fbd2f81d645d0ab42b34e27cde715613500"
    )
    #expect(
      table.meta.officialSchemaSha256
        == "4441d4dbaa6c5450ae9cbfb2438c53bc0421bba2b7fcc9ef9b158e5d1de0759e"
    )
    #expect(table.meta.oracle == "Tests/Conformance/oracle.py")
    #expect(table.meta.sourceFixture.contains("v1.2.0"))

    let constants = table.meta.constants
    #expect(constants.stringLength == Pikaid.stringLength)
    #expect(constants.binaryLength == Pikaid.binaryLength)
    #expect(constants.timestampChars == Pikaid.timestampCharacterCount)
    #expect(constants.randomnessChars == Pikaid.randomnessCharacterCount)
    #expect(constants.randomnessBytes == Pikaid.randomnessByteCount)
    #expect(constants.randomnessBits == 96)
    #expect(constants.base == 36)
    #expect(constants.maximumTimestamp == Pikaid.maximumTimestamp)
    #expect(constants.maximumTimestamp == 78_364_164_095)
    #expect(constants.maximumEntropyHex == "ffffffffffffffffffffffff")

    #expect(table.valid.count == 38)
    #expect(table.invalidString.count == 31)
    #expect(table.invalidBinary.count == 8)
    #expect(table.ordering.count == table.valid.count)
  }

  @Test("Table covers every required positive boundary")
  func requiredPositiveCoverage() {
    let required: Set<String> = [
      "all-zero",
      "timestamp-1-entropy-1",
      "max-values",
      "official-sample-1700000000",
      "timestamp-zero-max-entropy",
      "entropy-2^95",
      "maximum-timestamp-zero-entropy",
      "timestamp-max-minus-one",
      "timestamp-36^2-minus-one",
      "timestamp-36^2",
      "timestamp-2^31-minus-one",
      "timestamp-2^32-minus-one",
      "timestamp-2^32",
      "timestamp-36^6-minus-one",
      "timestamp-36^6",
      "entropy-leading-zeros",
      "entropy-leading-zero-byte",
      "entropy-max-minus-one",
      "timestamp-one-max-entropy",
      "ascending-0-timestamp-10",
      "descending-0-timestamp-24",
    ]
    #expect(Set(table.valid.map(\.name)).isSuperset(of: required))
  }

  @Test("Table covers every required negative form")
  func requiredNegativeCoverage() {
    let requiredStrings: Set<String> = [
      "empty",
      "length-25",
      "length-27",
      "length-100",
      "uppercase-at-6",
      "dash-at-6",
      "underscore-at-6",
      "space-at-25",
      "exclamation-at-12",
      "nul-at-12",
      "carriage-return-at-12",
      "line-feed-at-12",
      "crlf-at-11",
      "non-ascii-e-acute-2-byte",
      "zero-width-space-3-byte",
      "zero-width-joiner-3-byte",
      "byte-order-mark-3-byte",
      "fullwidth-digit-zero-3-byte",
      "entropy-2^96",
      "entropy-36^19-minus-1",
      "entropy-leading-8-overflow",
    ]
    #expect(Set(table.invalidString.map(\.name)).isSuperset(of: requiredStrings))

    let requiredBinary: Set<String> = [
      "length-0",
      "length-16",
      "length-18",
      "length-34",
      "timestamp-max-plus-one",
      "timestamp-2^40-minus-1",
    ]
    #expect(Set(table.invalidBinary.map(\.name)).isSuperset(of: requiredBinary))
  }

  @Test("Every positive row agrees across all public entrypoints and representations")
  func positiveRowsAgreeEverywhere() throws {
    for row in table.valid {
      let identifier = try Pikaid(string: row.id)

      #expect(identifier.timestamp == row.timestamp, "\(row.name)")
      #expect(identifier.randomnessHex == row.entropyHex, "\(row.name)")
      #expect(identifier.randomness == TestHex.bytes(row.entropyHex), "\(row.name)")
      #expect(identifier.string == row.id, "\(row.name)")
      #expect(identifier.description == row.id, "\(row.name)")
      #expect(TestHex.string(identifier.binary) == row.binHex, "\(row.name)")
      #expect(TestHex.string(identifier.binaryBytes) == row.binHex, "\(row.name)")
      #expect(identifier.binary.count == Pikaid.binaryLength, "\(row.name)")
      #expect(Pikaid.isValid(row.id), "\(row.name)")
      #expect(Pikaid.isWellFormed(row.id), "\(row.name)")

      let fromArray = try Pikaid(binary: TestHex.bytes(row.binHex))
      let fromData = try Pikaid(binary: Data(TestHex.bytes(row.binHex)))
      let fromComponents = try Pikaid(
        timestamp: row.timestamp,
        randomness: TestHex.bytes(row.entropyHex)
      )
      let fromComponentsData = try Pikaid(
        timestamp: row.timestamp,
        randomness: Data(TestHex.bytes(row.entropyHex))
      )

      for candidate in [fromArray, fromData, fromComponents, fromComponentsData] {
        #expect(candidate == identifier, "\(row.name)")
        #expect(candidate.string == row.id, "\(row.name)")
        #expect(TestHex.string(candidate.binary) == row.binHex, "\(row.name)")
        #expect(candidate.randomnessHex == row.entropyHex, "\(row.name)")
      }

      let encoded = try JSONEncoder().encode(identifier)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(row.id)\"", "\(row.name)")
      #expect(try JSONDecoder().decode(Pikaid.self, from: encoded) == identifier, "\(row.name)")

      let generated = try Pikaid.generate(
        timestamp: row.timestamp,
        using: StaticRandomnessSource(bytes: TestHex.bytes(row.entropyHex))
      )
      #expect(generated == identifier, "\(row.name)")
      #expect(generated.string == row.id, "\(row.name)")
    }
  }

  @Test("Every invalid string row is rejected with the oracle's error kind")
  func invalidStringsAreRejected() throws {
    for row in table.invalidString {
      #expect(!Pikaid.isValid(row.id), "\(row.name)")
      #expect(Pikaid.isWellFormed(row.id) == row.wellFormed, "\(row.name)")

      do {
        _ = try Pikaid(string: row.id)
        Issue.record("\(row.name) was accepted: \(row.id)")
      } catch let error as PikaidError {
        #expect(
          Self.errorKind(of: error) == row.expectedError,
          "\(row.name): expected \(row.expectedError), received \(error)"
        )
      } catch {
        Issue.record("\(row.name) threw a non-PikaidError: \(error)")
      }
    }
  }

  @Test("Every invalid binary row is rejected with the oracle's error kind")
  func invalidBinaryIsRejected() throws {
    for row in table.invalidBinary {
      let bytes = TestHex.bytes(row.binHex)

      do {
        _ = try Pikaid(binary: bytes)
        Issue.record("\(row.name) was accepted")
      } catch let error as PikaidError {
        #expect(
          Self.errorKind(of: error) == row.expectedError,
          "\(row.name): expected \(row.expectedError), received \(error)"
        )
      } catch {
        Issue.record("\(row.name) threw a non-PikaidError: \(error)")
      }

      do {
        _ = try Pikaid(binary: Data(bytes))
        Issue.record("\(row.name) was accepted through Data")
      } catch let error as PikaidError {
        #expect(Self.errorKind(of: error) == row.expectedError, "\(row.name) Data")
      } catch {
        Issue.record("\(row.name) Data threw a non-PikaidError: \(error)")
      }
    }
  }

  @Test("Oracle ordering matches value, string and binary comparison")
  func orderingMatchesOracle() throws {
    let identifiers = try table.valid.map { try Pikaid(string: $0.id) }

    #expect(identifiers.sorted().map(\.string) == table.ordering)
    #expect(identifiers.sorted { $0.string < $1.string }.map(\.string) == table.ordering)
    #expect(
      identifiers.sorted {
        $0.binaryBytes.lexicographicallyPrecedes($1.binaryBytes)
      }.map(\.string) == table.ordering
    )
  }

  @Test("Public generation entrypoints honour canonical timestamps")
  func publicGenerationHonoursTimestamps() throws {
    for row in table.valid.prefix(8) {
      let generated = try Pikaid.generate(timestamp: row.timestamp)
      #expect(generated.timestamp == row.timestamp, "\(row.name)")
      #expect(Pikaid.isValid(generated.string), "\(row.name)")
      #expect(generated.string.count == Pikaid.stringLength, "\(row.name)")
      #expect(generated.binary.count == Pikaid.binaryLength, "\(row.name)")

      let binary = try Pikaid.generateBinary(timestamp: row.timestamp)
      #expect(binary.count == Pikaid.binaryLength, "\(row.name)")
      #expect(try Pikaid(binary: binary).timestamp == row.timestamp, "\(row.name)")
    }
  }

  private static func errorKind(of error: PikaidError) -> String {
    switch error {
    case .invalidStringLength:
      return "invalidStringLength"
    case .invalidCharacter:
      return "invalidCharacter"
    case .invalidTimestamp:
      return "invalidTimestamp"
    case .invalidBinaryLength:
      return "invalidBinaryLength"
    case .timestampOverflow:
      return "timestampOverflow"
    case .randomnessOverflow:
      return "randomnessOverflow"
    case .invalidRandomnessLength:
      return "invalidRandomnessLength"
    case .randomnessUnavailable:
      return "randomnessUnavailable"
    }
  }
}

// MARK: - Table model

struct ConformanceTable: Decodable {
  struct Constants: Decodable {
    let stringLength: Int
    let binaryLength: Int
    let timestampChars: Int
    let randomnessChars: Int
    let randomnessBytes: Int
    let randomnessBits: Int
    let base: Int
    let maximumTimestamp: Int64
    let maximumEntropyHex: String
  }

  struct Meta: Decodable {
    let format: String
    let specRevision: String
    let specCommit: String
    let sourceFixture: String
    let officialFixtureSha256: String
    let officialSchemaSha256: String
    let oracle: String
    let oracleDescription: String
    let generatedBy: String
    let constants: Constants
    let notes: [String]
  }

  struct Valid: Decodable {
    let name: String
    let timestamp: Int64
    let entropyHex: String
    let id: String
    let binHex: String
  }

  struct InvalidString: Decodable {
    let name: String
    let id: String
    let utf8Hex: String
    let wellFormed: Bool
    let expectedError: String
  }

  struct InvalidBinary: Decodable {
    let name: String
    let binHex: String
    let expectedError: String
  }

  let meta: Meta
  let valid: [Valid]
  let ordering: [String]
  let invalidString: [InvalidString]
  let invalidBinary: [InvalidBinary]

  enum LoadError: Error {
    case missingFixture
  }

  static func load() throws -> ConformanceTable {
    guard
      let url = Bundle.module.url(
        forResource: "pikaid-conformance-v1",
        withExtension: "json"
      )
    else {
      throw LoadError.missingFixture
    }
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(ConformanceTable.self, from: data)
  }
}
