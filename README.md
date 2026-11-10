<p align="center">
  <img src="https://raw.githubusercontent.com/pikaid/pikaid-specs/v1.0.4/logo.png" alt="pikaid" width="300" />
</p>

<p align="center">
  <strong>Small · Sortable · Secure ID generator</strong>
</p>

# pikaid — Official Swift Implementation

**Status: implemented and validated, not yet released.** This repository is
private, has no tagged release, no published package, and no stable public API
guarantee yet. The current source is consumable only by branch or commit
reference with repository access; it is not a published Swift package.

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

### Independent conformance table

`Tests/Conformance/oracle.py` is a pure-Python big-integer reference
implementation. It does **not** import, execute, or read the Swift sources. It
generates and verifies the checked-in table
`Tests/PikaidTests/Fixtures/pikaid-conformance-v1.json`, which is pinned to:

- specification revision `1.0.4` at commit
  `17014d76f568c3ac9f9ce2927c1a018fdbc36d1d`;
- official PHP `v1.2.0` fixture digest
  `b0c9dfdd063613424414fef5c9065fbd2f81d645d0ab42b34e27cde715613500`;
- official schema digest
  `4441d4dbaa6c5450ae9cbfb2438c53bc0421bba2b7fcc9ef9b158e5d1de0759e`.

The table contains 38 valid rows, 31 invalid string rows, 8 invalid binary
rows, and an ordering list derived from the valid rows. It includes `0`,
`2^40 - 1`, `36^7 - 1`, `2^96`, `36^19 - 1`, leading-zero randomness, CRLF/LF,
NUL, and zero-width Unicode cases. Each valid row is checked through every
public entrypoint and representation. The oracle also performs a tamper
self-test, so a corrupted table or digest fails verification before the Swift
suite runs.

```sh
python3 Tests/Conformance/oracle.py --check
```

## Requirements

- Swift 6.0 or newer
- macOS 13 or newer, or Linux

The package has no external dependencies. On Apple platforms randomness is read
from `SecRandomCopyBytes`; elsewhere it uses Swift's system cryptographic
generator (`getrandom(2)` on Linux).

## Installation

Add the package to `Package.swift` (the repository must be accessible to the
consumer; it is not a public package registry entry):

```swift
dependencies: [
    .package(url: "https://github.com/pikaid/pikaid-swift.git", branch: "main")
]
```

No tagged release exists yet, so a branch or revision reference is required.
Pin a commit for reproducible builds; the dependency will move to a version
requirement only if a release is published.

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

## License

MIT. See [LICENSE](LICENSE).
