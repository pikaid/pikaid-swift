import Foundation

/// Process entry point for the test-only official conformance bridge.
///
/// The process is intentionally single-threaded and synchronous: one UTF-8 JSON
/// object on stdin produces exactly one flushed UTF-8 JSON object on stdout.
/// Diagnostics go to stderr only.
@main
struct ConformanceAdapterMain {
  static func main() {
    let adapter = PikaidAdapter()
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let stdout = FileHandle.standardOutput
    let stderr = FileHandle.standardError

    func emit(_ response: WireResponse) {
      do {
        let encoded = try encoder.encode(response)
        stdout.write(encoded)
        stdout.write(Data([0x0A]))
      } catch {
        stderr.write(Data("adapter: response encoding failed: \(error)\n".utf8))
        let fallback =
          "{\"request_id\":0,\"ok\":false,\"error\":{\"category\":\"internal_error\","
          + "\"message\":\"response encoding failed\"}}\n"
        stdout.write(Data(fallback.utf8))
      }
    }

    while let line = readLine(strippingNewline: true) {
      if line.isEmpty {
        continue
      }
      guard let data = line.data(using: .utf8) else {
        stderr.write(Data("adapter: request line is not valid UTF-8\n".utf8))
        emit(
          .failure(
            requestID: 0,
            category: "internal_error",
            message: "request line is not valid UTF-8"
          )
        )
        continue
      }

      do {
        let request = try decoder.decode(WireRequest.self, from: data)
        let response = adapter.response(for: request)
        if case .failure(_, let category, let message) = response,
          category == "internal_error"
        {
          stderr.write(
            Data(
              "adapter: internal_error for \(request.operation): \(message)\n".utf8
            )
          )
        }
        emit(response)
      } catch {
        stderr.write(Data("adapter: malformed request envelope: \(error)\n".utf8))
        emit(
          .failure(
            requestID: 0,
            category: "internal_error",
            message: "malformed request envelope"
          )
        )
      }
    }
  }
}
