/// Lowercase Base36 fixed-width encoding helpers.
enum Base36 {
  /// The permitted pikaid alphabet in ascending digit order.
  static let alphabet: [UInt8] = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)

  /// ASCII `0`.
  static let asciiZero: UInt8 = 0x30

  /// Lowercase hexadecimal digits used for randomness display.
  static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

  /// Byte-to-digit lookup. Negative entries are not valid Base36 bytes.
  private static let digitValues: [Int8] = {
    var table = [Int8](repeating: -1, count: 256)
    for (digit, byte) in alphabet.enumerated() {
      table[Int(byte)] = Int8(digit)
    }
    return table
  }()

  /// Returns the Base36 digit value of `byte`, or `nil` when it is invalid.
  @inline(__always)
  static func digitValue(of byte: UInt8) -> UInt8? {
    let value = digitValues[Int(byte)]
    return value >= 0 ? UInt8(value) : nil
  }

  /// Encodes a valid timestamp as exactly seven lowercase Base36 characters.
  static func encodeTimestamp(_ timestamp: Int64) -> [UInt8] {
    precondition(timestamp >= 0 && timestamp <= Pikaid.maximumTimestamp)
    var value = UInt64(timestamp)
    var digits = [UInt8](repeating: asciiZero, count: Pikaid.timestampCharacterCount)
    var index = digits.count - 1
    while value > 0 {
      digits[index] = alphabet[Int(value % 36)]
      value /= 36
      index -= 1
    }
    return digits
  }

  /// Encodes twelve randomness bytes as exactly nineteen lowercase Base36 characters.
  static func encodeRandomness(_ randomness: [UInt8]) -> [UInt8] {
    precondition(randomness.count == Pikaid.randomnessByteCount)
    var work = randomness
    var digits: [UInt8] = []
    digits.reserveCapacity(Pikaid.randomnessCharacterCount)

    while true {
      var remainder = 0
      var allZero = true
      for index in work.indices {
        let value = (remainder << 8) | Int(work[index])
        let quotient = value / 36
        remainder = value % 36
        work[index] = UInt8(quotient)
        if quotient != 0 {
          allZero = false
        }
      }
      digits.append(alphabet[remainder])
      if allZero {
        break
      }
    }

    precondition(digits.count <= Pikaid.randomnessCharacterCount)
    while digits.count < Pikaid.randomnessCharacterCount {
      digits.append(asciiZero)
    }
    digits.reverse()
    return digits
  }
}
