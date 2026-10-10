"""Validate a bhsim movie record (<movie>.mp4.json) against contracts/movie-record.schema.json.

Independent of the Swift code: uses the `jsonschema` package, so the record is checked by a full JSON-Schema
implementation rather than by the project's own tests.

    uv run python tools/reference/check_movie_record.py out/sweep.mp4.json
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA = Path(__file__).resolve().parents[2] / "specs/003-movie-from-frames/contracts/movie-record.schema.json"


def main(path: str) -> int:
    schema = json.loads(SCHEMA.read_text())
    Draft202012Validator.check_schema(schema)
    record = json.loads(Path(path).read_text())
    errors = sorted(Draft202012Validator(schema).iter_errors(record), key=lambda e: list(e.path))
    for e in errors:
        print(f"{'.'.join(str(p) for p in e.path) or '<root>'}: {e.message}")
    if errors:
        print(f"{path}: {len(errors)} schema violation(s)")
        return 1
    movie = record["movie"]
    print(f"{path}: valid ({record['source']}, {movie['frameCount']} frames, {movie['width']}x{movie['height']}, "
          f"encoder {movie['encoder']['name']} {movie['encoder']['version']})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
