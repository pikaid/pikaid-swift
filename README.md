<p align="center">
  <a href="https://github.com/pikaid/pikaid-specs">
    <img src="https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/logo.png" alt="pikaid" width="300">
  </a>
</p>

<p align="center">
  <strong>Small · Sortable · Secure ID generator</strong>
</p>

<div align="center">

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/language-Swift-F05138.svg)](https://github.com/pikaid/pikaid-swift)
[![CI](https://github.com/pikaid/pikaid-swift/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pikaid/pikaid-swift/actions/workflows/ci.yml)
[![Official implementation](https://img.shields.io/badge/official-implementation-2e7d32.svg)](https://github.com/pikaid/pikaid-specs)
[![Specification 1.0.4](https://img.shields.io/badge/spec-1.0.4-4b56a6.svg)](https://github.com/pikaid/pikaid-specs/tree/v1.0.4)

</div>

**pikaid** is the **official Swift implementation** of a compact, chronologically sortable, collision-resistant identifier format for databases, APIs, and distributed systems.

This is the immutable, unversioned [pikaid format](https://github.com/pikaid/pikaid-specs/tree/v1.0.4), documented in specification revision **1.0.4**.

## ✨ Why pikaid?

- **Short:** Compact, readable IDs for URLs, logs, and API resources.
- **Sortable:** Lexicographically ordered by timestamp, with **one-second precision**.
- **Collision-resistant:** 96 bits of cryptographic randomness make collisions extremely unlikely, never impossible.
- **Storage-friendly:** Use `BINARY(17)` or readable `CHAR(26)`.
- **Distributed-friendly:** No central sequence generator or coordination required.

## 🧬 Identifier format

A pikaid contains **26 lowercase Base36 characters**: a **7-character Unix-seconds timestamp** followed by **19 characters encoding 96 bits of cryptographic randomness**. Its binary form is **17 bytes**: 5 unsigned big-endian timestamp bytes followed by 12 randomness bytes.

![Identifier structure](https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/structure.svg)

> **Ordering:** Different seconds sort chronologically. Within the same second, randomness—not issuance order—decides the order.

> **Security:** These are identifiers, **not secrets**, session credentials, authentication tokens, or API keys.

## ⚙️ Requirements

- Swift 6.0 or newer
- macOS 13 or newer, or Linux

The package has no external dependencies. On Apple platforms randomness is read
from `SecRandomCopyBytes`; elsewhere it uses Swift's system cryptographic
generator (`getrandom(2)` on Linux).

## 📦 Installation

This is a public Swift Package Manager Git dependency (not a package-registry release). In your application's `Package.swift`, add:

```swift
dependencies: [
    .package(url: "https://github.com/pikaid/pikaid-swift.git", branch: "main")
]
```

Use the branch or pin a specific commit for reproducible builds.
Pin a commit for reproducible builds; the dependency will move to a version
requirement only if a release is published.

```swift
.target(
    name: "YourTarget",
    dependencies: [.product(name: "Pikaid", package: "pikaid-swift")]
)
```

For an executable target, save the quick start below in `Sources/main.swift` and run `swift run`. To validate the package directly from its repository, use:

```sh
git clone https://github.com/pikaid/pikaid-swift.git
cd pikaid-swift
swift test
```

## 🚀 Basic Usage

In your Swift Package Manager executable target, use this complete example:

```swift
import Pikaid

let id = try Pikaid.generate()
assert(Pikaid.isValid(id.string))
let binary = id.binary
assert(binary.count == 17)
let restored = try Pikaid(binary: binary)
assert(restored == id)
print(id.string, id.timestamp)
```

Values vary on each run because generation uses the operating-system CSPRNG.

## 💡 Example Use Case

Use pikaid to identify **users, orders, invoices, uploads, events, and API resources**. Independent services can generate compact IDs without a shared counter, while timestamp-based ordering helps with indexing, sorting, and logs.

## 📚 Canonical specification

- [Canonical specification](https://github.com/pikaid/pikaid-specs)
- [Revision 1.0.4](https://github.com/pikaid/pikaid-specs/tree/v1.0.4)

Specification revisions describe the format; they do not change the encoded identifiers.

## 🧩 API Reference

### Specification contract → public API

| Specification concept | Public API |
| --------------------- | ---------- |
| 26-character canonical string | `Pikaid.string`, `Pikaid(string:)`, `description`, `Codable` |
| 17-byte binary `[5 BE timestamp][12 randomness]` | `Pikaid.binary`, `Pikaid.binaryBytes`, `Pikaid(binary:)` |
| 7-digit timestamp `0...36^7-1` | `Pikaid.timestamp`, `Pikaid.generate(timestamp:)`, `Pikaid(timestamp:randomness:)` |
| 19-digit / 96-bit randomness | `Pikaid.randomness`, `Pikaid.randomnessHex` |
| Strict rejection without coercion | Throwing initializers, `PikaidError` |
| Shape vs semantic validation | `Pikaid.isWellFormed(_:)` vs `Pikaid.isValid(_:)` |
| Timestamp-then-randomness order | `Comparable`, canonical string order, unsigned binary order |
| UTC whole-second timestamp | `Pikaid.timestamp` is Unix seconds; map with `Date(timeIntervalSince1970:)` |

The implementation deliberately exposes no separate `Date` property or
generation-order counter: the format has one-second precision and same-second
order is defined by randomness, not creation time.

### Members

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

assert(fromString == fromBinary)
assert(fromString == fromBytes)
assert(fromString == rebuilt)
assert(fromString.description == fromString.string)
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
import Foundation

let sample = try Pikaid(string: "0s44we8002loz3po6mcf6vsn23")
let data = try JSONEncoder().encode(sample)   // "\"0s44we8002loz3po6mcf6vsn23\""
let decoded = try JSONDecoder().decode(Pikaid.self, from: data)
assert(decoded == sample)
```

## 🔄 Order Guarantee

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

## 🛢 Storage Recommendations

| Representation | Size | Recommended for |
| --- | ---: | --- |
| **BINARY(17)** | 17 bytes | Compact primary keys and indexes |
| **CHAR(26)** | 26 characters | Readable SQL, debugging, URLs, and logs |

Use an **ASCII bytewise/binary collation** for text columns (for example, `ascii_bin` on MariaDB/MySQL). Case-insensitive or locale-aware sorting is not a substitute for canonical bytewise comparison.

## ✅ Verification and release status

The [CI workflow](https://github.com/pikaid/pikaid-swift/actions/workflows/ci.yml) runs Swift tests, pinned automated conformance checks, and package and sanitizer checks. To run the native checks locally from a checkout, use `swift test`.

**Automated passing tests are not a security certification.** The independent CSPRNG source and failure-path audits (`P-GENERATE-RNG-SOURCE` and `P-GENERATE-RNG-FAILURE`) still require separate human evidence.

<details>
<summary>Platform, tooling, and conformance details</summary>

The test suite is written with [Swift Testing](https://github.com/swiftlang/swift-testing)
and covers:

- the pinned independent conformance table: 38 valid, 31 invalid string, 8
  invalid binary, and 38 ordering entries, each valid row exercised through
  string, binary, components, `Codable`, validation, generation, and comparison;
- every official PHP v1.2.0 interoperability vector (`valid` and `invalid`,
  string and binary), copied verbatim into `Tests/PikaidTests/Fixtures`;
- the examples published in this README, executed against the public module;
- known answers produced by an independent Python Base36 oracle, including
  timestamp and randomness boundaries;
- strict validation: lengths, alphabet, uppercase, separators, non-ASCII input,
  zero-width Unicode, CRLF, timestamp overflow, and 96-bit randomness overflow;
- lossless string/binary/component round trips and `Codable`;
- generation, CSPRNG failure paths, and injected randomness;
- ordering equivalence between value, string, and binary comparison;
- randomized property tests for round trips, mutations, and overflow suffixes.

A test-only bridge package under `Tests/ConformanceAdapter` exposes those same
public APIs over the official JSON-Lines adapter protocol, so the upstream
`pikaid-specs` suite can drive this implementation. It is a separate package
and never part of the published product; see its README for the capability
mapping and for the one capability that is deliberately unadvertised.

Run the suite:

```sh
python3 Tests/Conformance/oracle.py --check
swift build -c release -Xswiftc -warnings-as-errors
swift test
swift test -c release
swift test --sanitize=address
swift format lint --recursive --strict Sources Tests Package.swift
```

Line coverage of the library sources is **283/287 = 98.61%** (`swift test
--enable-code-coverage`), with `Pikaid.swift` at 99.43%, `Base36.swift` at
100%, `PikaidError.swift` at 100%, and `RandomnessSource.swift` at 88.46%. CI
enforces a **90% library line-coverage floor** on Linux with Swift 6.1; the job
fails if coverage drops below it.

The suite contains **73 tests in 9 suites**. It has been executed on:

- macOS 27.2 arm64 with the Swift 6.4.2 Command Line Tools toolchain (debug,
  release, and AddressSanitizer), and
- Linux in `swift:6.1.3` containers, natively on
  `aarch64-unknown-linux-gnu` and under `linux/amd64` emulation on
  `x86_64-unknown-linux-gnu`, with a warnings-as-errors release build and the
  debug and release test suites passing on both. The non-Apple randomness path
  is therefore exercised by fresh local execution, not only by CI declaration.
  Swift 6.0.3 on `aarch64` also passes the release build and release tests; its
  debug suite passes when the Swift 6.0 toolchain's intermittent module-cache
  error (`SwiftShims` defined twice) does not occur.

The GitHub Actions workflow defines:

- the release build with warnings as errors and the debug and release test
  suites on `ubuntu-latest` (Swift 6.0 and 6.1), `macos-15` arm64
  (`Xcode_16.2`/`16.4`), and `macos-15-intel` x86_64 (`Xcode_16.4`);
- a conformance job that verifies the pinned fixture digests, runs
  `oracle.py --check`, and executes the conformance and README suites;
- an official-conformance job that fetches `pikaid/pikaid-specs` by the exact
  commit `059780cc0e5b113443812720d95c630649bf3aa3`, verifies the suite
  checksums, schema and declared revisions, runs the suite's own tests and its
  independent Node oracle, builds the test-only JSON-Lines adapter in
  `Tests/ConformanceAdapter` with warnings as errors, runs the official
  adapter suite, and asserts the exact case counts plus the two CSPRNG audit
  obligations it deliberately leaves to manual evidence;
- an AddressSanitizer job;
- a coverage job with the 90% floor;
- an external-consumer job that builds `swift package archive-source`, extracts
  the archive outside the checkout, and runs a separate executable target
  against it; and
- a packaging-hygiene job that asserts `.ai/` is untracked, matched by the
  explicit root `/.ai/` ignore rule, absent from the archive, that tracked text
  uses LF, that no local absolute paths or credentials are tracked, that
  `Package.swift` does not bake a Command Line Tools plugin path, that required
  files are present in the archive, and that pinned files are byte-identical to
  the checkout.

The declared minimum is macOS 13. The oldest macOS version exercised by this
repository is macOS 15, on both arm64 and x86_64. macOS 13 and 14 remain
supported by declaration, not verified at runtime: GitHub retired the macOS 14
runner images on 2026-11-02 and the macOS 13 images earlier, so hosted CI can no
longer execute those versions. The code uses only Foundation and `Security`
APIs available since macOS 10.7 and is compiled with a macOS 13 deployment
target; runtime proof for macOS 13 or 14 requires a host running that version.

The `.ai/` directory is local agent scratch space and execution reports. It is
ignored explicitly via the root `/.ai/` rule and is not part of the package,
the source archive, or the public API.

### Command Line Tools note

A full Xcode installation or a swift.org toolchain runs the tests directly. On a
Command Line Tools–only macOS installation the bundled `TestingMacros` plugin
lives in a `plugins/testing` subdirectory that SwiftPM does not scan, so the
tests need the search path supplied explicitly:

```sh
swift test -Xswiftc -plugin-path \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

</details>

Registry publication is not implied by a green CI: use the Git dependency documented above.

## 🤝 Contributing

Contributions are always welcome! 💙

Whether you're fixing a typo, improving documentation, adding tests, or making pikaid even better, every contribution is appreciated.

**Want to help? Here's how:**

- 🐛 **Found a bug?** [Open an issue](https://github.com/pikaid/pikaid-swift/issues) with clear reproduction steps.
- 💡 **Have an idea?** Start with an issue before making major changes.
- 🛠️ **Ready to contribute?** Open a pull request explaining your changes.
- 🧪 **Keep it tested.** Add meaningful regression tests for behavior changes and follow the existing conventions.
- ✅ **Make sure CI passes.** All required checks must be green before a pull request is merged. No shortcuts!

**One important rule:** pikaid's identifier format is immutable. Contributions must preserve the [canonical specification (revision 1.0.4)](https://github.com/pikaid/pikaid-specs/tree/v1.0.4).

🔐 **Found a security vulnerability?** Report it privately using GitHub's security reporting (when available), or [contact the maintainer](mailto:larananas.dev@proton.me)—not through a public issue.

**Every improvement matters, big or small. Thanks for helping make pikaid better!** 🐇

## 📄 License

The implementation is available under the [MIT License](LICENSE).

## ✉️ Contact

For licensing or project-related questions: [larananas.dev@proton.me](mailto:larananas.dev@proton.me).

