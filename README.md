<p align="center">
  <img src="https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/logo.png" alt="pikaid" width="300" />
</p>

<p align="center">
  <strong>Small · Sortable · Secure ID generator</strong>
</p>

# pikaid — Official Swift Implementation

**Status: implemented and validated, not yet released.** There is no tagged
release, published package, or stable public API guarantee yet.

This repository contains the **official Swift implementation** of
[pikaid](https://github.com/pikaid), a compact, chronologically sortable
identifier format for databases, APIs, and distributed systems.

The pikaid identifier format is immutable and unversioned: **26 lowercase
Base36 characters** with a **17-byte binary representation**.

```text
0s44we8002loz3po6mcf6vsn23
└──┬──┘└─────────┬────────┘
   7 chars      19 chars
 timestamp    96 bits of randomness
```

## Canonical specification

The authoritative definition is [pikaid specification revision
1.0.4](https://github.com/pikaid/pikaid-specs/tree/v1.0.4), pinned in this
repository at commit `17014d76f568c3ac9f9ce2927c1a018fdbc36d1d`.

This implementation follows the specification. The official
[PHP v1.2.0 conformance vectors](https://github.com/pikaid/pikaid-php) are used
as independent interoperability fixtures, not as an API template.

## Requirements

- Swift 6.0 or newer
- macOS 13 or newer, or Linux

The package has no external dependencies. On Apple platforms randomness is read
from `SecRandomCopyBytes`; elsewhere it uses Swift's system cryptographic
generator (`getrandom(2)` on Linux).

## Installation

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pikaid/pikaid-swift.git", branch: "main")
]
```

No tagged release exists yet, so a branch or revision reference is required.
Pin a commit for reproducible builds; the dependency will move to a version
requirement once a release is published.

```swift
.target(
    name: "YourTarget",
    dependencies: [.product(name: "Pikaid", package: "pikaid-swift")]
)
```

## Usage

### Generate

```swift
import Pikaid

let id = try Pikaid.generate()
print(id.string)          // 26 lowercase Base36 characters (varies per call)
print(id.timestamp)       // current Unix time in whole seconds
print(id.randomnessHex)   // 24 hex characters from the CSPRNG
```

A concrete identifier, the official `sample-1700000000` interoperability vector,
is `0s44we8002loz3po6mcf6vsn23` with timestamp `1700000000`.

Generation reads the current Unix time in whole seconds and 12 bytes from the
platform CSPRNG. A caller-supplied timestamp is still range-checked and still
uses fresh CSPRNG entropy, so its suffix is not predictable:

```swift
let fixed = try Pikaid.generate(timestamp: 1_700_000_000)
let bytes = try Pikaid.generateBinary()                 // 17 bytes
let fixedBytes = try Pikaid.generateBinary(timestamp: 1_700_000_000)
```

### Parse and convert

```swift
let fromString = try Pikaid(string: "zzzzzzz7oiylpimjg5u2ca1ypr")
let fromBinary = try Pikaid(binary: fromString.binary)   // Data, 17 bytes
let fromBytes = try Pikaid(binary: fromString.binaryBytes)

let rebuilt = try Pikaid(
    timestamp: fromString.timestamp,
    randomness: fromString.randomness
)

#expect(fromString == fromBinary)
#expect(fromString == fromBytes)
#expect(fromString == rebuilt)
#expect(fromString.description == fromString.string)
```

`binary` returns `Data` and `binaryBytes` returns `[UInt8]`; both use the
canonical layout `[5-byte big-endian timestamp][12 randomness bytes]`.
`randomness` keeps the original bytes, including leading zeros.

### Validate

```swift
Pikaid.isValid("0s44we8002loz3po6mcf6vsn23")       // true
Pikaid.isValid("000000A0000000000000000000")       // false — uppercase
Pikaid.isValid("0000000zzzzzzzzzzzzzzzzzzz")       // false — randomness > 96 bits

Pikaid.isWellFormed("0000000zzzzzzzzzzzzzzzzzzz")  // true — shape only
```

`isValid(_:)` performs the full check: length, alphabet, timestamp range, and
the 96-bit randomness limit. `isWellFormed(_:)` only checks the 26-character
lowercase Base36 shape, so a `true` result does **not** mean the value is a
valid pikaid.

Strict operations throw `PikaidError` rather than truncating, wrapping,
lowercasing, or otherwise normalizing input:

```swift
do {
    _ = try Pikaid(string: "0000000000000000000000000")  // 25 characters
} catch let error as PikaidError {
    print(error.errorDescription ?? "")
}
```

### Compare

`Pikaid` is `Comparable`. Different timestamps sort chronologically; within the
same second the unsigned randomness decides order. This is identical to ASCII
comparison of the strings and to unsigned bytewise comparison of the binary
forms.

### Codable

`Pikaid` encodes as its canonical string and rejects invalid strings when
decoding:

```swift
let sample = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
let data = try JSONEncoder().encode(sample)   // "\"0s44we8002loz3po6mcf6vsn23\""
let decoded = try JSONDecoder().decode(Pikaid.self, from: data)
#expect(decoded == sample)
```

## API summary

| Member | Description |
| ------ | ----------- |
| `Pikaid(string:)` | Parse and fully validate a 26-character string |
| `Pikaid(binary:)` | Parse and validate 17 `Data` or `[UInt8]` bytes |
| `Pikaid(timestamp:randomness:)` | Build from components; range and length checked |
| `Pikaid.generate()` / `generate(timestamp:)` | Generate from the CSPRNG |
| `generateBinary()` / `generateBinary(timestamp:)` | Generate the 17-byte form |
| `Pikaid.isValid(_:)` | Boolean full validation |
| `Pikaid.isWellFormed(_:)` | Boolean shape check only |
| `.string`, `.binary`, `.binaryBytes` | Canonical representations |
| `.timestamp`, `.randomness`, `.randomnessHex` | Decoded fields |
| `.maximumTimestamp` | `78_364_164_095` (`36^7 - 1`) |
| `.stringLength`, `.binaryLength` | `26` and `17` |

## Security and ordering caveats

- pikaid values are **not secrets**, authentication tokens, or authorization
  mechanisms. The timestamp is readable from the identifier.
- 96 bits of CSPRNG randomness reduce accidental collisions; they do **not**
  guarantee uniqueness. Enforce uniqueness where required, for example with a
  database primary key or unique constraint.
- Identifiers generated in the **same second** are ordered by their random
  suffix, not by generation order. pikaid is **not a monotonic sequence
  generator**.
- The timestamp has **one-second precision**. There is no sub-second component.
- There is no checksum. A transcription mistake can produce another valid
  identifier.
- For text storage use a binary or verified ASCII-compatible collation. Default
  database collations are not automatically safe for bytewise ordering.

## Conformance and testing

The test suite is written with [Swift Testing](https://github.com/swiftlang/swift-testing)
and covers:

- every official PHP v1.2.0 interoperability vector (`valid` and `invalid`,
  string and binary), copied verbatim into `Tests/PikaidTests/Fixtures`;
- known answers produced by an independent Python Base36 oracle, including
  timestamp and randomness boundaries;
- strict validation: lengths, alphabet, uppercase, separators, non-ASCII input,
  timestamp overflow, and 96-bit randomness overflow;
- lossless string/binary/component round trips and `Codable`;
- generation, CSPRNG failure paths, and injected randomness;
- ordering equivalence between value, string, and binary comparison;
- randomized property tests for round trips, mutations, and overflow suffixes.

Run the suite:

```sh
swift build -c release -Xswiftc -warnings-as-errors
swift test
swift format lint --recursive --strict Sources Tests Package.swift
```

Line coverage of the library sources is **98.6%** (`swift test
--enable-code-coverage`), with `Pikaid.swift` and `Base36.swift` at or above
99%.

The suite has been executed on:

- macOS 27.2 arm64 with the Swift 6.4.2 Command Line Tools toolchain (debug and
  release), and
- Linux `aarch64-unknown-linux-gnu` in a `swift:6.1.3` container (debug and
  release), which also exercises the non-Apple randomness path.

The GitHub Actions matrix runs Swift 6.0 and 6.1 on Ubuntu and macOS.

### Command Line Tools note

A full Xcode installation or a swift.org toolchain runs the tests directly. On a
Command Line Tools–only macOS installation the bundled `TestingMacros` plugin
lives in a `plugins/testing` subdirectory that SwiftPM does not scan, so the
tests need the search path supplied explicitly:

```sh
swift test -Xswiftc -plugin-path \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## License

MIT. See [LICENSE](LICENSE).
