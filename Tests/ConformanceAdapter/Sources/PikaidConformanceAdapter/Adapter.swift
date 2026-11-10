import Foundation
import Pikaid

/// Test-only bridge from the official JSON-Lines protocol to the real public
/// `Pikaid` API.
///
/// Every operation delegates to `Pikaid` itself. The bridge only performs
/// wire-level work the protocol requires: JSON parsing, lowercase hex
/// conversion, and ISO-8601 UTC formatting of a decoded timestamp.
struct PikaidAdapter {
  /// Advertised capabilities, limited to operations with a real public mapping.
  ///
  /// `csprng_failure_injection` is intentionally absent: the production
  /// randomness protocol is internal, no public RNG seam exists, and adding one
  /// solely for this bridge is forbidden. Failure-path coverage stays in the
  /// native `GenerationTests` suite; the official suite records the
  /// corresponding audit as manual evidence required.
  static let capabilities: [String] = [
    "generate_string",
    "text_to_binary",
    "binary_to_text",
    "boolean_validation",
    "format_only_validation",
    "parse_components",
    "parse_datetime",
    "generate_with_timestamp",
    "generate_binary",
    "generate_binary_with_timestamp",
    "public_compare",
  ]

  private static let lowercaseHexDigits = Array("0123456789abcdef".utf8)

  private let iso8601Formatter: ISO8601DateFormatter

  init() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    iso8601Formatter = formatter
  }

  /// Handles one request and maps all failures to the documented categories.
  func response(for request: WireRequest) -> WireResponse {
    do {
      let value = try perform(
        request.operation,
        arguments: request.arguments ?? [:]
      )
      return .success(requestID: request.requestID, value: value)
    } catch let error as AdapterError {
      return .failure(
        requestID: request.requestID,
        category: category(for: error),
        message: message(for: error)
      )
    } catch let error as PikaidError {
      // A genuine entropy-source failure is not an input rejection. Every other
      // PikaidError is a documented validation/range failure.
      let category = error == .randomnessUnavailable ? "entropy_unavailable" : "invalid_input"
      return .failure(
        requestID: request.requestID,
        category: category,
        message: error.localizedDescription
      )
    } catch {
      return .failure(
        requestID: request.requestID,
        category: "internal_error",
        message: "unexpected bridge failure: \(error)"
      )
    }
  }

  // MARK: - Operations

  private func perform(
    _ operation: String,
    arguments: [String: JSONValue]
  ) throws -> JSONValue {
    switch operation {
    case "hello":
      return .object([
        "protocol_version": .int(1),
        "capabilities": .array(Self.capabilities.map(JSONValue.string)),
      ])

    case "generate_string":
      return .string(try Pikaid.generate().string)

    case "text_to_binary":
      let text = try stringArgument(arguments, "text")
      let identifier = try Pikaid(string: text)
      return .string(Self.hexString(identifier.binaryBytes))

    case "binary_to_text":
      let hex = try stringArgument(arguments, "binary_hex")
      let bytes = try Self.decodeLowercaseHex(hex)
      let identifier = try Pikaid(binary: bytes)
      return .string(identifier.string)

    case "boolean_validation":
      let text = try stringArgument(arguments, "text")
      return .bool(Pikaid.isValid(text))

    case "format_only_validation":
      let text = try stringArgument(arguments, "text")
      return .bool(Pikaid.isWellFormed(text))

    case "parse_components":
      let text = try stringArgument(arguments, "text")
      let identifier = try Pikaid(string: text)
      return .object([
        "timestamp_seconds": .int(identifier.timestamp),
        "randomness_hex": .string(identifier.randomnessHex),
        "datetime_utc": .string(Self.utcString(identifier.timestamp, using: iso8601Formatter)),
      ])

    case "generate_with_timestamp":
      let timestamp = try integerArgument(arguments, "timestamp_seconds")
      return .string(try Pikaid.generate(timestamp: timestamp).string)

    case "generate_binary":
      return .string(Self.hexString(Array(try Pikaid.generateBinary())))

    case "generate_binary_with_timestamp":
      let timestamp = try integerArgument(arguments, "timestamp_seconds")
      return .string(Self.hexString(Array(try Pikaid.generateBinary(timestamp: timestamp))))

    case "public_compare":
      let a = try Pikaid(string: try stringArgument(arguments, "a"))
      let b = try Pikaid(string: try stringArgument(arguments, "b"))
      let result: Int64
      if a < b {
        result = -1
      } else if a > b {
        result = 1
      } else {
        result = 0
      }
      return .int(result)

    default:
      throw AdapterError.unsupportedOperation("unsupported operation: \(operation)")
    }
  }

  // MARK: - Argument decoding

  private func stringArgument(
    _ arguments: [String: JSONValue],
    _ key: String
  ) throws -> String {
    guard case .string(let value)? = arguments[key] else {
      throw AdapterError.invalidInput("argument '\(key)' must be a string")
    }
    return value
  }

  private func integerArgument(
    _ arguments: [String: JSONValue],
    _ key: String
  ) throws -> Int64 {
    guard case .int(let value)? = arguments[key] else {
      throw AdapterError.invalidInput("argument '\(key)' must be an integer")
    }
    return value
  }

  // MARK: - Wire conversions

  /// Strict lowercase hex decoding. Any other character is a wire-level input
  /// error; length and timestamp validation still happen in `Pikaid`.
  private static func decodeLowercaseHex(_ hex: String) throws -> [UInt8] {
    let characters = Array(hex.utf8)
    guard characters.count % 2 == 0 else {
      throw AdapterError.invalidInput(
        "binary_hex must contain an even number of lowercase hexadecimal digits"
      )
    }
    var bytes = [UInt8]()
    bytes.reserveCapacity(characters.count / 2)
    var index = 0
    while index < characters.count {
      guard
        let high = nibble(characters[index]),
        let low = nibble(characters[index + 1])
      else {
        throw AdapterError.invalidInput(
          "binary_hex must contain only lowercase hexadecimal digits"
        )
      }
      bytes.append((high << 4) | low)
      index += 2
    }
    return bytes
  }

  private static func nibble(_ character: UInt8) -> UInt8? {
    switch character {
    case 0x30...0x39:
      return character - 0x30
    case 0x61...0x66:
      return character - 0x61 + 10
    default:
      return nil
    }
  }

  private static func hexString(_ bytes: [UInt8]) -> String {
    var characters = [UInt8]()
    characters.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      characters.append(lowercaseHexDigits[Int(byte >> 4)])
      characters.append(lowercaseHexDigits[Int(byte & 0x0F)])
    }
    return String(decoding: characters, as: UTF8.self)
  }

  /// ISO-8601 UTC second for a decoded timestamp.
  ///
  /// Verified against the full legal range, including `0` and
  /// `Pikaid.maximumTimestamp` (year 4453); `Date` stores the integer second
  /// exactly and the formatter emits a `Z` suffix.
  private static func utcString(
    _ timestamp: Int64,
    using formatter: ISO8601DateFormatter
  ) -> String {
    formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
  }

  // MARK: - Error mapping

  private func category(for error: AdapterError) -> String {
    switch error {
    case .invalidInput:
      return "invalid_input"
    case .unsupportedOperation:
      return "unsupported_operation"
    case .internalFailure:
      return "internal_error"
    }
  }

  private func message(for error: AdapterError) -> String {
    switch error {
    case .invalidInput(let message):
      return message
    case .unsupportedOperation(let message):
      return message
    case .internalFailure(let message):
      return message
    }
  }
}
