import Foundation

/// Errors thrown while validating, converting, or generating a pikaid.
///
/// Every failure is explicit: pikaid never truncates, wraps, normalizes, or
/// otherwise coerces invalid input into a valid identifier.
public enum PikaidError: Error, Equatable, Sendable {
  /// A string is not exactly 26 UTF-8 bytes long.
  case invalidStringLength(actual: Int, expected: Int)

  /// A string contains a byte outside the lowercase Base36 alphabet.
  case invalidCharacter(byte: UInt8, index: Int)

  /// A supplied timestamp is negative or greater than `36^7 - 1`.
  case invalidTimestamp(Int64)

  /// A binary value is not exactly 17 bytes long.
  case invalidBinaryLength(actual: Int, expected: Int)

  /// A five-byte binary timestamp exceeds `36^7 - 1`.
  case timestampOverflow(UInt64)

  /// A nineteen-character suffix decodes to a value larger than 96 bits.
  case randomnessOverflow

  /// A randomness source returned the wrong number of bytes.
  case invalidRandomnessLength(actual: Int, expected: Int)

  /// The platform cryptographic source failed, or a randomness source threw.
  case randomnessUnavailable
}

extension PikaidError: LocalizedError {
  /// A human-readable description of the validation or generation failure.
  public var errorDescription: String? {
    switch self {
    case .invalidStringLength(let actual, let expected):
      return "A pikaid must be exactly \(expected) ASCII characters; received \(actual)."
    case .invalidCharacter(let byte, let index):
      let display: String
      if (0x20...0x7E).contains(byte) {
        display = "'\(Character(UnicodeScalar(byte)))'"
      } else {
        display = String(format: "0x%02x", byte)
      }
      return
        "Invalid character \(display) at byte \(index); only lowercase Base36 [0-9a-z] is allowed."
    case .invalidTimestamp(let timestamp):
      return
        "Timestamp \(timestamp) is outside the valid pikaid range 0...\(Pikaid.maximumTimestamp)."
    case .invalidBinaryLength(let actual, let expected):
      return "A binary pikaid must be exactly \(expected) bytes; received \(actual)."
    case .timestampOverflow(let timestamp):
      return
        "Binary timestamp \(timestamp) exceeds the maximum pikaid timestamp \(Pikaid.maximumTimestamp)."
    case .randomnessOverflow:
      return "The randomness suffix exceeds the 96-bit pikaid randomness range."
    case .invalidRandomnessLength(let actual, let expected):
      return "A randomness source must return exactly \(expected) bytes; received \(actual)."
    case .randomnessUnavailable:
      return "The cryptographic randomness source was unavailable."
    }
  }
}
