"""Regenerates HarborIOSTests/StreamEngineVectorsData.swift from the golden JSON.

The JSON is produced by the Rust vector-extractor (rust/vector-extractor):
  cargo run   (in rust/vector-extractor, with the GNU toolchain on PATH)

Usage: python scripts/embed_vectors.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "Tests" / "Fixtures" / "stream-engine-vectors.json"
OUT_PATH = ROOT / "HarborIOSTests" / "StreamEngineVectorsData.swift"

def main() -> int:
    text = JSON_PATH.read_text(encoding="utf-8")
    if '#"' in text:
        print("ERROR: JSON contains raw-string terminator '#\"'", file=sys.stderr)
        return 1
    swift = (
        "// GENERATED FILE — do not edit. Regenerate with: python scripts/embed_vectors.py\n"
        "import Foundation\n\n"
        "let streamEngineVectorsJSON = #\"\"\"\n" + text + "\n\"\"\"#\n"
    )
    OUT_PATH.write_text(swift, encoding="utf-8", newline="")
    print(f"OK: {OUT_PATH} ({len(swift)} bytes) from {JSON_PATH}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
