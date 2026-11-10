# Changelog

All notable changes to this package are documented in this file. Versions follow
[Semantic Versioning](https://semver.org/).

## 1.0.0 — unreleased

Initial release candidate. The source is implemented and locally validated, but
it is **not tagged and not published**. The repository is private, and any
publication or `v1.0.0` tag requires an owner decision. This file does not claim
that a distributable release exists.

### Added

- Official Swift implementation of pikaid v1, specification revision 1.0.4.
- Canonical 26-character lowercase Base36 strings and 17-byte binary values
  (five big-endian timestamp bytes plus twelve randomness bytes).
- Strict, non-normalizing validation with explicit `PikaidError` cases for
  length, alphabet, timestamp range, 96-bit randomness overflow, and invalid
  binary input.
- CSPRNG-only generation through `SecRandomCopyBytes` on Apple platforms and
  Swift's system generator on Linux, failing closed on source errors.
- `Codable`, `Comparable`, `Hashable`, `Sendable`, and `CustomStringConvertible`
  conformances.
- Pinned conformance table (`pikaid-conformance-v1.json`) generated and verified
  by an independent pure-Python big-integer oracle. The table is pinned to
  specification 1.0.4 and the official PHP v1.2.0 fixture and schema digests,
  and the oracle includes a tamper self-test.
- Conformance cases covering zero, `2^40 - 1`, `36^7 - 1`, `2^96`,
  `36^19 - 1`, leading-zero randomness, CRLF/LF, NUL, and zero-width Unicode,
  exercised through every public entrypoint and representation.
- README example tests executed against the public module.
- CI jobs for conformance/oracle verification, AddressSanitizer, an external
  consumer of the packed source archive, and expanded packaging hygiene.
- `.gitattributes` LF normalization for checked-in text, keeping fixture and
  conformance-table digests stable across platforms.

### Fixed

- Restored the explicit root `/.ai/` ignore rule after a broad `/.??/` pattern
  replaced it. Local agent scratch space and execution reports are again
  ignored without hiding legitimate root dotfiles such as `.spi.yml`.

### Validation

- 73 tests in 9 suites, including 38 valid, 31 invalid string, and 8 invalid
  binary conformance rows plus 38 ordering entries.
- 283/287 library lines covered (98.61%) on the audit host.
- Debug, release, and AddressSanitizer runs executed locally on macOS 27.2
  arm64 with Swift 6.4.2 (Command Line Tools).
- `.ai/` is absent from the source archive; required files are present and
  shared provenance files are byte-identical to the checkout.
