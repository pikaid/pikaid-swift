import Foundation

@testable import Pikaid

// MARK: - Randomness sources used to exercise failure paths

struct StaticRandomnessSource: RandomnessSource {
  let bytes: [UInt8]

  func randomBytes(count: Int) throws -> [UInt8] {
    Array(bytes.prefix(count))
  }
}

struct FailingRandomnessSource: RandomnessSource {
  struct Failure: Error {}

  func randomBytes(count: Int) throws -> [UInt8] {
    throw Failure()
  }
}

struct WrongLengthRandomnessSource: RandomnessSource {
  let bytes: [UInt8]

  func randomBytes(count: Int) throws -> [UInt8] {
    bytes
  }
}

// MARK: - Hex helpers (independent of the library's own formatting)

enum TestHex {
  static func bytes(_ hex: String) -> [UInt8] {
    precondition(hex.count.isMultiple(of: 2), "Hex input must have an even number of digits")
    var result: [UInt8] = []
    result.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else {
        preconditionFailure("Invalid hex input: \(hex)")
      }
      result.append(byte)
      index = next
    }
    return result
  }

  static func string(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      output.append(digits[Int(byte >> 4)])
      output.append(digits[Int(byte & 0x0F)])
    }
    return String(decoding: output, as: UTF8.self)
  }

  static func string(_ data: Data) -> String {
    string([UInt8](data))
  }
}

// MARK: - Official interoperability vectors

struct PikaidVectorFile: Decodable {
  struct Meta: Decodable {
    struct Timestamp: Decodable {
      let encoding: String
      let chars: Int
      let min: Int64
      let max: Int64
    }

    struct Entropy: Decodable {
      let bytes: Int
      let encoding: String
      let chars: Int
    }

    struct Binary: Decodable {
      let bytes: Int
      let layout: String
    }

    let project: String
    let stringLength: Int
    let timestamp: Timestamp
    let entropy: Entropy
    let binary: Binary
    let specRevision: String
    let identifierFormat: String
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
  }

  struct InvalidBinary: Decodable {
    let name: String
    let binHex: String
  }

  struct Invalid: Decodable {
    let string: [InvalidString]
    let binary: [InvalidBinary]
  }

  let meta: Meta
  let valid: [Valid]
  let invalid: Invalid
}

enum PikaidVectors {
  enum LoadError: Error {
    case missingFixture
  }

  static func load() throws -> PikaidVectorFile {
    // Fixtures are copied file by file, so they land at the resource root.
    guard let url = Bundle.module.url(forResource: "pikaid-v1", withExtension: "json") else {
      throw LoadError.missingFixture
    }
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(PikaidVectorFile.self, from: data)
  }
}
