#!/usr/bin/env python3
"""Independent pikaid conformance oracle and table generator.

This script is deliberately written in pure Python using arbitrary-precision
integers. It never imports, executes, or reads the Swift implementation under
test. It is the independent reference used to produce and verify
``Tests/PikaidTests/Fixtures/pikaid-conformance-v1.json``.

Commands
--------
``--write``  Regenerate the checked-in conformance table from this oracle.
``--check``  Verify the checked-in table, the pinned official fixture digests,
             the official PHP v1.2.0 vectors, and a built-in tamper self-test.

The table and oracle are consumed by the GitHub Actions ``conformance`` job and
by the Swift ``Pinned conformance table`` test suite.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import pathlib
import sys
from typing import Any

# --- Pinned specification and fixture identity -------------------------------

SPEC_REVISION = "1.0.4"
SPEC_COMMIT = "17014d76f568c3ac9f9ce2927c1a018fdbc36d1d"
SOURCE_FIXTURE = "pikaid/pikaid-php v1.2.0 (e3f843edeb5157a5d2d25196cac0d69580810a95)"
OFFICIAL_FIXTURE_SHA256 = "b0c9dfdd063613424414fef5c9065fbd2f81d645d0ab42b34e27cde715613500"
OFFICIAL_SCHEMA_SHA256 = "4441d4dbaa6c5450ae9cbfb2438c53bc0421bba2b7fcc9ef9b158e5d1de0759e"

# --- Format constants --------------------------------------------------------

BASE = 36
ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"
DIGIT_VALUES = {character: value for value, character in enumerate(ALPHABET)}
STRING_LENGTH = 26
TIMESTAMP_CHARS = 7
RANDOMNESS_CHARS = 19
RANDOMNESS_BYTES = 12
RANDOMNESS_BITS = 96
BINARY_LENGTH = 17
MAXIMUM_TIMESTAMP = BASE**TIMESTAMP_CHARS - 1  # 36^7 - 1
MAXIMUM_ENTROPY = 2**RANDOMNESS_BITS - 1  # 2^96 - 1

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURE_DIRECTORY = REPOSITORY_ROOT / "Tests" / "PikaidTests" / "Fixtures"
TABLE_PATH = FIXTURE_DIRECTORY / "pikaid-conformance-v1.json"
OFFICIAL_FIXTURE_PATH = FIXTURE_DIRECTORY / "pikaid-v1.json"
OFFICIAL_SCHEMA_PATH = FIXTURE_DIRECTORY / "pikaid-v1.schema.json"


# --- Reference implementation ------------------------------------------------


def to_base36(value: int, width: int) -> str:
    """Encode a non-negative integer as fixed-width lowercase Base36."""
    if value < 0:
        raise ValueError("negative value")
    digits: list[str] = []
    remaining = value
    while remaining:
        remaining, remainder = divmod(remaining, BASE)
        digits.append(ALPHABET[remainder])
    encoded = "".join(reversed(digits)) or "0"
    if len(encoded) > width:
        raise ValueError(f"value {value} does not fit in {width} Base36 digits")
    return encoded.rjust(width, "0")


def from_base36(text: str) -> int:
    """Decode lowercase Base36, raising on any non-alphabet character."""
    value = 0
    for character in text:
        value = value * BASE + DIGIT_VALUES[character]
    return value


def encode(timestamp: int, entropy: bytes) -> tuple[str, str]:
    """Return the canonical string and binary hex for one value."""
    if not 0 <= timestamp <= MAXIMUM_TIMESTAMP:
        raise ValueError("timestamp out of range")
    if len(entropy) != RANDOMNESS_BYTES:
        raise ValueError("entropy must be exactly twelve bytes")
    identifier = to_base36(timestamp, TIMESTAMP_CHARS) + to_base36(
        int.from_bytes(entropy, "big"), RANDOMNESS_CHARS
    )
    binary = timestamp.to_bytes(5, "big") + entropy
    return identifier, binary.hex()


def decode_string(identifier: str) -> tuple[int, bytes]:
    """Decode a canonical string, rejecting every non-conforming input."""
    raw = identifier.encode("utf-8")
    if len(raw) != STRING_LENGTH:
        raise ValueError("invalidStringLength")
    for byte in raw:
        if not (0x30 <= byte <= 0x39 or 0x61 <= byte <= 0x7A):
            raise ValueError("invalidCharacter")
    timestamp = from_base36(identifier[:TIMESTAMP_CHARS])
    if timestamp > MAXIMUM_TIMESTAMP:
        raise ValueError("timestampOverflow")
    entropy_value = from_base36(identifier[TIMESTAMP_CHARS:])
    if entropy_value > MAXIMUM_ENTROPY:
        raise ValueError("randomnessOverflow")
    return timestamp, entropy_value.to_bytes(RANDOMNESS_BYTES, "big")


def decode_binary(binary: bytes) -> tuple[int, bytes]:
    """Decode the canonical 17-byte binary form."""
    if len(binary) != BINARY_LENGTH:
        raise ValueError("invalidBinaryLength")
    timestamp = int.from_bytes(binary[:5], "big")
    if timestamp > MAXIMUM_TIMESTAMP:
        raise ValueError("timestampOverflow")
    return timestamp, binary[5:]


def is_well_formed(identifier: str) -> bool:
    """Shape-only check: exactly 26 ASCII lowercase Base36 bytes."""
    raw = identifier.encode("utf-8")
    if len(raw) != STRING_LENGTH:
        return False
    return all(0x30 <= byte <= 0x39 or 0x61 <= byte <= 0x7A for byte in raw)


def classify_string(identifier: str) -> tuple[str | None, bool]:
    """Return (expected error name or None, shape-only well-formed flag)."""
    raw = identifier.encode("utf-8")
    if len(raw) != STRING_LENGTH:
        return "invalidStringLength", False
    for byte in raw:
        if not (0x30 <= byte <= 0x39 or 0x61 <= byte <= 0x7A):
            return "invalidCharacter", False
    entropy_value = from_base36(identifier[TIMESTAMP_CHARS:])
    if entropy_value > MAXIMUM_ENTROPY:
        return "randomnessOverflow", True
    return None, True


def classify_binary(binary: bytes) -> str | None:
    """Return the expected error name for an invalid binary value."""
    if len(binary) != BINARY_LENGTH:
        return "invalidBinaryLength"
    if int.from_bytes(binary[:5], "big") > MAXIMUM_TIMESTAMP:
        return "timestampOverflow"
    return None


# --- Conformance corpus ------------------------------------------------------


def build_valid_cases() -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []

    def add(name: str, timestamp: int, entropy: bytes) -> None:
        identifier, binary_hex = encode(timestamp, entropy)
        cases.append(
            {
                "name": name,
                "timestamp": timestamp,
                "entropy_hex": entropy.hex(),
                "id": identifier,
                "bin_hex": binary_hex,
            }
        )

    zero = bytes(RANDOMNESS_BYTES)
    ones = b"\xff" * RANDOMNESS_BYTES

    # Required specification boundaries and official fixture rows.
    add("all-zero", 0, zero)
    add("timestamp-1-entropy-1", 1, (1).to_bytes(RANDOMNESS_BYTES, "big"))
    add("max-values", MAXIMUM_TIMESTAMP, ones)
    add(
        "official-sample-1700000000",
        1_700_000_000,
        bytes.fromhex("00112233445566778899aabb"),
    )

    # Timestamp boundaries around powers and Base36 digit transitions.
    add("timestamp-zero-max-entropy", 0, ones)
    add("entropy-2^95", 0, (2**95).to_bytes(RANDOMNESS_BYTES, "big"))
    add("maximum-timestamp-zero-entropy", MAXIMUM_TIMESTAMP, zero)
    add("timestamp-max-minus-one", MAXIMUM_TIMESTAMP - 1, ones)
    add("timestamp-36^2-minus-one", BASE**2 - 1, zero)
    add("timestamp-36^2", BASE**2, zero)
    add("timestamp-2^31-minus-one", 2**31 - 1, bytes.fromhex("7f" * RANDOMNESS_BYTES))
    add("timestamp-2^32-minus-one", 2**32 - 1, zero)
    add("timestamp-2^32", 2**32, zero)
    add("timestamp-36^6-minus-one", BASE**6 - 1, zero)
    add("timestamp-36^6", BASE**6, zero)

    # Randomness boundaries and leading-zero preservation.
    add("entropy-leading-zeros", 1_234_567_890, bytes.fromhex("00000000000000000000000a"))
    add("entropy-leading-zero-byte", 42, bytes.fromhex("00ff000000000000000000ff"))
    add("entropy-max-minus-one", 1_000, (MAXIMUM_ENTROPY - 1).to_bytes(RANDOMNESS_BYTES, "big"))
    add("timestamp-one-max-entropy", 1, ones)
    add("real-world-week", 604_800, bytes.fromhex("00ff00ff00ff00ff00ff00ff"))

    # Fixed ascending timestamps.
    ascending_entropy = bytes.fromhex("fedcba9876543210fedcba98")
    for index, timestamp in enumerate([10, 11, 12, 13, 14]):
        add(f"ascending-{index}-timestamp-{timestamp}", timestamp, ascending_entropy)

    # Fixed descending timestamps with a different suffix.
    descending_entropy = bytes.fromhex("0123456789abcdef01234567")
    for index, timestamp in enumerate([24, 23, 22, 21, 20]):
        add(f"descending-{index}-timestamp-{timestamp}", timestamp, descending_entropy)

    # Deterministic rows derived with SHA-256 so the table is independent of
    # the Python version's pseudorandom generator implementation.
    for index in range(8):
        digest = hashlib.sha256(
            f"pikaid-conformance-20261109-{index}".encode("ascii")
        ).digest()
        timestamp = int.from_bytes(digest[:8], "big") % (MAXIMUM_TIMESTAMP + 1)
        entropy = digest[8:20]
        add(f"seeded-{index}", timestamp, entropy)

    identifiers = [case["id"] for case in cases]
    assert len(identifiers) == len(set(identifiers)), "duplicate conformance identifiers"
    return cases


def build_invalid_string_cases() -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    zero = "0"

    def add(name: str, identifier: str) -> None:
        expected, well_formed = classify_string(identifier)
        assert expected is not None, f"{name} unexpectedly valid"
        cases.append(
            {
                "name": name,
                "id": identifier,
                "utf8_hex": identifier.encode("utf-8").hex(),
                "well_formed": well_formed,
                "expected_error": expected,
            }
        )

    # Length boundaries.
    add("empty", "")
    add("length-1", zero)
    add("length-25", zero * 25)
    add("length-27", zero * 27)
    add("length-100", zero * 100)

    # Alphabet: uppercase and punctuation.
    add("uppercase-at-6", "000000A0000000000000000000")
    add("uppercase-at-25", zero * 25 + "Z")
    add("dash-at-6", "000000-0000000000000000000")
    add("underscore-at-6", "000000_0000000000000000000")
    add("space-at-25", zero * 25 + " ")
    add("exclamation-at-12", zero * 12 + "!" + zero * 13)
    add("dot-at-12", zero * 12 + "." + zero * 13)
    add("slash-at-12", zero * 12 + "/" + zero * 13)
    add("tilde-at-12", zero * 12 + "~" + zero * 13)
    add("plus-at-12", zero * 12 + "+" + zero * 13)
    add("colon-at-12", zero * 12 + ":" + zero * 13)

    # Control characters, whitespace and CRLF / LF.
    add("nul-at-12", zero * 12 + "\x00" + zero * 13)
    add("tab-at-12", zero * 12 + "\t" + zero * 13)
    add("carriage-return-at-12", zero * 12 + "\r" + zero * 13)
    add("line-feed-at-12", zero * 12 + "\n" + zero * 13)
    add("crlf-at-11", zero * 11 + "\r\n" + zero * 13)

    # Non-ASCII and zero-width Unicode.
    add("non-ascii-e-acute-2-byte", zero * 24 + "\u00e9")
    add("non-ascii-e-acute-27-bytes", zero * 25 + "\u00e9")
    add("zero-width-space-3-byte", zero * 23 + "\u200b")
    add("zero-width-joiner-3-byte", zero * 23 + "\u200d")
    add("byte-order-mark-3-byte", zero * 23 + "\ufeff")
    add("fullwidth-digit-zero-3-byte", zero * 23 + "\uff10")

    # Semantically invalid but shape-valid randomness suffixes.
    add("entropy-2^96", zero * 7 + to_base36(2**RANDOMNESS_BITS, RANDOMNESS_CHARS))
    add("entropy-2^96-plus-one", zero * 7 + to_base36(2**RANDOMNESS_BITS + 1, RANDOMNESS_CHARS))
    add("entropy-36^19-minus-1", zero * 7 + "z" * RANDOMNESS_CHARS)
    add("entropy-leading-8-overflow", zero * 7 + "8" + zero * 18)

    return cases


def build_invalid_binary_cases() -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []

    def add(name: str, binary_hex: str) -> None:
        expected = classify_binary(bytes.fromhex(binary_hex))
        assert expected is not None, f"{name} unexpectedly valid"
        cases.append(
            {
                "name": name,
                "bin_hex": binary_hex,
                "expected_error": expected,
            }
        )

    add("length-0", "")
    add("length-16", "00" * 16)
    add("length-18", "00" * 18)
    add("length-34", "00" * 34)
    add("timestamp-max-plus-one", "123ede4000" + "00" * 12)
    add("timestamp-2^39", "8000000000" + "00" * 12)
    add("timestamp-2^40-minus-2", "fffffffffe" + "00" * 12)
    add("timestamp-2^40-minus-1", "ffffffffff" + "00" * 12)

    return cases


def build_table() -> dict[str, Any]:
    valid = build_valid_cases()
    ordering = [
        case["id"]
        for case in sorted(
            valid,
            key=lambda case: (case["timestamp"], bytes.fromhex(case["entropy_hex"])),
        )
    ]
    return {
        "meta": {
            "format": "pikaid-conformance-v1",
            "spec_revision": SPEC_REVISION,
            "spec_commit": SPEC_COMMIT,
            "source_fixture": SOURCE_FIXTURE,
            "official_fixture_sha256": OFFICIAL_FIXTURE_SHA256,
            "official_schema_sha256": OFFICIAL_SCHEMA_SHA256,
            "oracle": "Tests/Conformance/oracle.py",
            "oracle_description": (
                "Pure-Python big-integer reference implementation. It does not "
                "import or execute the Swift sources under test."
            ),
            "generated_by": "python3 Tests/Conformance/oracle.py --write",
            "constants": {
                "string_length": STRING_LENGTH,
                "binary_length": BINARY_LENGTH,
                "timestamp_chars": TIMESTAMP_CHARS,
                "randomness_chars": RANDOMNESS_CHARS,
                "randomness_bytes": RANDOMNESS_BYTES,
                "randomness_bits": RANDOMNESS_BITS,
                "base": BASE,
                "maximum_timestamp": MAXIMUM_TIMESTAMP,
                "maximum_entropy_hex": "f" * (RANDOMNESS_BYTES * 2),
            },
            "notes": [
                "Seven Base36 timestamp digits cannot exceed 36^7 - 1, so timestamp "
                "overflow is only reachable through the binary form.",
                "isWellFormed is shape-only: it is true for any 26 ASCII Base36 "
                "characters, even when randomness exceeds 96 bits.",
                "Same-second order follows unsigned randomness, not generation order.",
            ],
        },
        "valid": valid,
        "ordering": ordering,
        "invalid_string": build_invalid_string_cases(),
        "invalid_binary": build_invalid_binary_cases(),
    }


def render(table: dict[str, Any]) -> str:
    return json.dumps(table, indent=2, ensure_ascii=True) + "\n"


# --- Verification ------------------------------------------------------------


def sha256_of(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_pins() -> list[str]:
    failures: list[str] = []
    if sha256_of(OFFICIAL_FIXTURE_PATH) != OFFICIAL_FIXTURE_SHA256:
        failures.append("official pikaid-v1.json digest does not match the pinned value")
    if sha256_of(OFFICIAL_SCHEMA_PATH) != OFFICIAL_SCHEMA_SHA256:
        failures.append("official pikaid-v1.schema.json digest does not match the pinned value")
    return failures


def verify_official_fixture() -> list[str]:
    failures: list[str] = []
    document = json.loads(OFFICIAL_FIXTURE_PATH.read_text(encoding="utf-8"))

    meta = document["meta"]
    if meta["spec_revision"] != SPEC_REVISION:
        failures.append("official fixture spec_revision drifted")
    if meta["string_length"] != STRING_LENGTH:
        failures.append("official fixture string_length drifted")
    if meta["timestamp"]["max"] != MAXIMUM_TIMESTAMP:
        failures.append("official fixture maximum timestamp drifted")
    if meta["entropy"]["bytes"] != RANDOMNESS_BYTES:
        failures.append("official fixture randomness byte count drifted")
    if meta["binary"]["bytes"] != BINARY_LENGTH:
        failures.append("official fixture binary length drifted")

    for vector in document["valid"]:
        try:
            encoded = encode(vector["timestamp"], bytes.fromhex(vector["entropy_hex"]))
        except ValueError as error:  # pragma: no cover - defensive
            failures.append(f"{vector['name']}: oracle rejected valid vector: {error}")
            continue
        if encoded != (vector["id"], vector["bin_hex"]):
            failures.append(f"{vector['name']}: oracle encoding disagrees with official vector")
        if decode_string(vector["id"]) != (
            vector["timestamp"],
            bytes.fromhex(vector["entropy_hex"]),
        ):
            failures.append(f"{vector['name']}: oracle string decode disagrees")
        if decode_binary(bytes.fromhex(vector["bin_hex"])) != (
            vector["timestamp"],
            bytes.fromhex(vector["entropy_hex"]),
        ):
            failures.append(f"{vector['name']}: oracle binary decode disagrees")

    for vector in document["invalid"]["string"]:
        if classify_string(vector["id"])[0] is None:
            failures.append(f"{vector['name']}: oracle accepted an official invalid string")
    for vector in document["invalid"]["binary"]:
        if classify_binary(bytes.fromhex(vector["bin_hex"])) is None:
            failures.append(f"{vector['name']}: oracle accepted an official invalid binary")

    return failures


def verify_table_against_oracle(table: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    expected = build_table()
    if table.get("meta") != expected["meta"]:
        failures.append("table metadata does not match the oracle")
    if table.get("valid") != expected["valid"]:
        failures.append("valid rows do not match the oracle")
    if table.get("ordering") != expected["ordering"]:
        failures.append("ordering does not match the oracle")
    if table.get("invalid_string") != expected["invalid_string"]:
        failures.append("invalid string rows do not match the oracle")
    if table.get("invalid_binary") != expected["invalid_binary"]:
        failures.append("invalid binary rows do not match the oracle")
    return failures


def tamper_self_test(table: dict[str, Any]) -> list[str]:
    """Prove the checker notices a corrupted table and a corrupted digest."""
    failures: list[str] = []

    mutated_identifier = copy.deepcopy(table)
    original = mutated_identifier["valid"][0]["id"]
    replacement = ("a" if original[0] != "a" else "b") + original[1:]
    mutated_identifier["valid"][0]["id"] = replacement
    if not verify_table_against_oracle(mutated_identifier):
        failures.append("tamper self-test did not detect a mutated identifier")

    mutated_digest = copy.deepcopy(table)
    mutated_digest["meta"]["official_fixture_sha256"] = "0" * 64
    if not verify_table_against_oracle(mutated_digest):
        failures.append("tamper self-test did not detect a mutated fixture digest")

    return failures


# --- Entry point -------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="write the conformance table")
    group.add_argument("--check", action="store_true", help="verify the conformance table")
    arguments = parser.parse_args(argv)

    if arguments.write:
        table = build_table()
        TABLE_PATH.write_text(render(table), encoding="utf-8")
        print(f"wrote {TABLE_PATH.relative_to(REPOSITORY_ROOT)}")
        print(f"valid={len(table['valid'])}")
        print(f"invalid_string={len(table['invalid_string'])}")
        print(f"invalid_binary={len(table['invalid_binary'])}")
        return 0

    failures: list[str] = []
    failures.extend(verify_pins())
    failures.extend(verify_official_fixture())

    if not TABLE_PATH.exists():
        failures.append(f"missing conformance table: {TABLE_PATH}")
        table = None
    else:
        table = json.loads(TABLE_PATH.read_text(encoding="utf-8"))
        failures.extend(verify_table_against_oracle(table))
        failures.extend(tamper_self_test(table))

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    assert table is not None
    print("pinned conformance table verified against the independent oracle")
    print(f"spec_revision={SPEC_REVISION} spec_commit={SPEC_COMMIT}")
    print(f"official_fixture_sha256={OFFICIAL_FIXTURE_SHA256}")
    print(f"official_schema_sha256={OFFICIAL_SCHEMA_SHA256}")
    print(f"valid={len(table['valid'])}")
    print(f"invalid_string={len(table['invalid_string'])}")
    print(f"invalid_binary={len(table['invalid_binary'])}")
    print(f"ordering={len(table['ordering'])}")
    print("tamper_self_test=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
