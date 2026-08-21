#!/usr/bin/env python3
"""Initialize a non-destructive Android passkey investigation record."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--title", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--hypothesis", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    content = f"""# {args.title}

- Date: {args.date}
- Status: in progress
- Hypothesis: {args.hypothesis}

## Question and scope

TBD

## Configuration

### Local and upstream revisions

TBD

### Device, apps, and provider

TBD

### Relying party

TBD

## Experiment design

| Case | Control or treatment | Expected falsifier | Result |
| --- | --- | --- | --- |
| TBD | TBD | TBD | TBD |

## Reproduction

```text
TBD
```

## Observations and evidence

TBD

## Result and causal assessment

TBD

## Remaining uncertainty and next experiment

TBD

## Artifacts and hashes

TBD

## Tests and warnings

TBD

## GCP resources and cleanup

Not used.
"""
    try:
        with args.output.open("x", encoding="utf-8", errors="strict", newline="\n") as record:
            record.write(content)
    except FileExistsError:
        raise SystemExit(f"refusing to replace existing record: {args.output}")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
