# Official conformance adapter (test-only)

This directory contains the test-only bridge that lets the official PikaID
conformance suite drive the real public `Pikaid` API over the JSON-Lines
adapter protocol (v1).

It is a **separate Swift package** on purpose:

- the production `Package.swift` gains no executable target, no test-only
  dependency, and no Python/Node coupling;
- the bridge lives under `Tests/`, is never a library product, and is never
  installed by consumers;
- every operation calls `Pikaid` itself. The bridge only performs wire-level
  work: JSON parsing, strict lowercase-hex decoding, and ISO-8601 UTC
  formatting of a decoded timestamp.

## Build and run

```sh
# From the repository root:
swift build --package-path Tests/ConformanceAdapter -c release \
  -Xswiftc -warnings-as-errors

# The official suite's runner launches the adapter as a subprocess:
python3 tools/run_adapter.py --automated-only \
  --report-json "$RUNNER_TEMP/conformance-report.json" \
  -- "$PWD/Tests/ConformanceAdapter/.build/release/PikaidConformanceAdapter"
```

The runner and the pinned fixture revision are fetched by exact commit in CI;
nothing from the official suite is vendored into this repository.

## Capability mapping

| Capability | Real public API |
| --- | --- |
| `generate_string` | `Pikaid.generate().string` |
| `text_to_binary` | `Pikaid(string:)` then `binaryBytes` |
| `binary_to_text` | `Pikaid(binary:)` then `string` |
| `boolean_validation` | `Pikaid.isValid(_:)` |
| `format_only_validation` | `Pikaid.isWellFormed(_:)` |
| `parse_components` | `Pikaid(string:)` fields `timestamp` and `randomnessHex` |
| `parse_datetime` | `ISO8601DateFormatter` (UTC) over the decoded `timestamp` |
| `generate_with_timestamp` | `Pikaid.generate(timestamp:)` |
| `generate_binary` | `Pikaid.generateBinary()` |
| `generate_binary_with_timestamp` | `Pikaid.generateBinary(timestamp:)` |
| `public_compare` | `Pikaid(string:)` plus `<` / `==` |

## Deliberately unadvertised: `csprng_failure_injection`

The production randomness protocol (`RandomnessSource`) is internal, and both
`generate()` overloads construct `SystemRandomnessSource` themselves. There is
no public seam for injecting a failing entropy source, and adding one solely
for this bridge would weaken the production API.

The suite therefore records `P-GENERATE-RNG-FAILURE` as
`MANUAL_EVIDENCE_REQUIRED` instead of pretending the capability exists. The
fail-closed path is covered natively by `Tests/PikaidTests/GenerationTests.swift`
using an internal failing source; the review conclusion for both CSPRNG audits
belongs in the release report, not in a fabricated adapter result.

See `Tests/PikaidTests/GenerationTests.swift` and
`Sources/Pikaid/RandomnessSource.swift` for the production failure handling.
