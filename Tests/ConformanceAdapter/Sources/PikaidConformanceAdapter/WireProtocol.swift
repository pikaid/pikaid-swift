import Foundation

/// One JSON value from the adapter protocol.
///
/// The bridge parses arguments with `JSONDecoder` instead of `JSONSerialization`
/// so booleans, integers, and strings keep their wire types. That matters for
/// `timestamp_seconds` (must be an integer), capability results (must be a real
/// boolean), and strict error envelopes.
enum JSONValue: Codable {
  case string(String)
  case int(Int64)
  case double(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
      return
    }
    if let value = try? container.decode(Int64.self) {
      self = .int(value)
      return
    }
    if let value = try? container.decode(Double.self) {
      self = .double(value)
      return
    }
    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }
    if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
      return
    }
    if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "unsupported JSON value"
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }
}

/// One request line from the official runner.
struct WireRequest: Decodable {
  let requestID: Int
  let operation: String
  let arguments: [String: JSONValue]?

  enum CodingKeys: String, CodingKey {
    case requestID = "request_id"
    case operation
    case arguments
  }
}

/// Exactly one success or failure envelope per request.
enum WireResponse: Encodable {
  case success(requestID: Int, value: JSONValue)
  case failure(requestID: Int, category: String, message: String)

  enum CodingKeys: String, CodingKey {
    case requestID = "request_id"
    case ok
    case value
    case error
  }

  enum ErrorKeys: String, CodingKey {
    case category
    case message
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .success(let requestID, let value):
      try container.encode(requestID, forKey: .requestID)
      try container.encode(true, forKey: .ok)
      try container.encode(value, forKey: .value)
    case .failure(let requestID, let category, let message):
      try container.encode(requestID, forKey: .requestID)
      try container.encode(false, forKey: .ok)
      var error = container.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
      try error.encode(category, forKey: .category)
      try error.encode(message, forKey: .message)
    }
  }
}

/// Errors raised by the bridge itself before or instead of a library failure.
enum AdapterError: Error {
  /// A malformed wire argument or an argument type the protocol forbids.
  case invalidInput(String)
  /// The operation exists but this bridge deliberately does not advertise it.
  case unsupportedOperation(String)
  /// A defect in the bridge, not a rejection of user input.
  case internalFailure(String)
}
