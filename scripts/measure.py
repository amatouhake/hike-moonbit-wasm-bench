#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import gzip
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Artifact:
    name: str
    file: str
    category: str


ARTIFACTS = [
    Artifact("Hike Fib (article commit)", "hike-fib-article.wasm", "fib"),
    Artifact("MoonBit Fib (wasm)", "moonbit-fib-wasm.wasm", "fib"),
    Artifact("MoonBit Fib (wasm-gc)", "moonbit-fib-wasm-gc.wasm", "fib"),
    Artifact("Hike browser (article commit)", "hike-browser-article.wasm", "browser"),
    Artifact("Hike browser (latest pinned)", "hike-browser-latest.wasm", "browser"),
    Artifact("MoonBit browser (wasm-gc)", "moonbit-browser-wasm-gc.wasm", "browser"),
]

PAYLOADS = [
    ("Hike browser (article commit)", ["hike-browser-article.wasm", "hike-browser-article.runtime.js"]),
    ("Hike browser (latest pinned)", ["hike-browser-latest.wasm", "hike-browser-latest.runtime.js"]),
    ("MoonBit browser (wasm-gc)", ["moonbit-browser-wasm-gc.wasm", "moonbit-browser-host.mjs"]),
]


def gzip_size(data: bytes) -> int:
    return len(gzip.compress(data, compresslevel=9, mtime=0))


def brotli_size(data: bytes) -> int | None:
    proc = subprocess.run(
        ["brotli", "--quality=11", "--stdout"],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    return len(proc.stdout) if proc.returncode == 0 else None


def sizes(path: Path) -> tuple[int, int, int | None]:
    data = path.read_bytes()
    return len(data), gzip_size(data), brotli_size(data)


def fmt(n: int | None) -> str:
    return "—" if n is None else f"{n:,} B"


def md_table(headers: list[str], rows: list[list[str]]) -> str:
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--csv", type=Path, required=True)
    ap.add_argument("--markdown", type=Path, required=True)
    ap.add_argument("--metadata", type=Path, required=True)
    args = ap.parse_args()

    rows: list[dict[str, object]] = []
    table_rows: list[list[str]] = []

    for artifact in ARTIFACTS:
        path = args.out / artifact.file
        if not path.exists():
            if artifact.file == "hike-browser-latest.wasm" and (args.out / "hike-browser-latest.ERROR.txt").exists():
                continue
            raise SystemExit(f"missing expected artifact: {path}")
        raw, gz, br = sizes(path)
        rows.append({"name": artifact.name, "variant": "compiler output", "file": artifact.file, "raw_bytes": raw, "gzip_bytes": gz, "brotli_bytes": br or ""})
        table_rows.append([artifact.name, artifact.file, fmt(raw), fmt(gz), fmt(br)])

        oz = path.with_name(path.stem + ".oz.wasm")
        if oz.exists():
            o_raw, o_gz, o_br = sizes(oz)
            rows.append({"name": artifact.name, "variant": "wasm-opt -Oz", "file": oz.name, "raw_bytes": o_raw, "gzip_bytes": o_gz, "brotli_bytes": o_br or ""})
            table_rows.append([artifact.name + " + `wasm-opt -Oz`", oz.name, fmt(o_raw), fmt(o_gz), fmt(o_br)])

    payload_rows: list[list[str]] = []
    for name, files in PAYLOADS:
        if not all((args.out / f).exists() for f in files):
            continue
        metrics = [sizes(args.out / f) for f in files]
        raw = sum(x[0] for x in metrics)
        gz = sum(x[1] for x in metrics)
        br_values = [x[2] for x in metrics]
        br = sum(x for x in br_values if x is not None) if all(x is not None for x in br_values) else None
        payload_rows.append([name, " + ".join(f"`{f}`" for f in files), fmt(raw), fmt(gz), fmt(br)])

        wasm = args.out / files[0]
        oz = wasm.with_name(wasm.stem + ".oz.wasm")
        if oz.exists():
            oz_files = [oz.name, *files[1:]]
            oz_metrics = [sizes(args.out / f) for f in oz_files]
            o_raw = sum(x[0] for x in oz_metrics)
            o_gz = sum(x[1] for x in oz_metrics)
            o_br_values = [x[2] for x in oz_metrics]
            o_br = sum(x for x in o_br_values if x is not None) if all(x is not None for x in o_br_values) else None
            payload_rows.append([name + " + `wasm-opt -Oz`", " + ".join(f"`{f}`" for f in oz_files), fmt(o_raw), fmt(o_gz), fmt(o_br)])

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["name", "variant", "file", "raw_bytes", "gzip_bytes", "brotli_bytes"])
        w.writeheader()
        w.writerows(rows)

    metadata = args.metadata.read_text(encoding="utf-8").rstrip()
    failure_files = sorted(args.out.glob("*.ERROR.txt"))
    failures = ""
    if failure_files:
        blocks = []
        for failure in failure_files:
            blocks.append(
                f"### `{failure.name}`\n\n```text\n{failure.read_text(encoding='utf-8').rstrip()}\n```"
            )
        failures = "\n\n## Build failures / regressions observed\n\n" + "\n\n".join(blocks)

    md = f"""# Latest benchmark results

Generated by GitHub Actions from pinned source revisions. The primary number is the **raw `.wasm` byte size**; gzip and Brotli are included because transfer size can matter more on the web.

## Individual WebAssembly modules

{md_table(["Workload", "Artifact", "Raw", "gzip -9", "Brotli q11"], table_rows)}

## Browser delivery payload

This includes the host-side JavaScript required by each browser sample. Compression is calculated per file and then summed, matching separate HTTP resources rather than concatenating them first.

{md_table(["Workload", "Files", "Raw total", "gzip total", "Brotli total"], payload_rows)}

## Interpretation rules

- **Fibonacci is the strictest apples-to-apples size comparison.** It contains one recursive integer computation and one exported entry point.
- The browser workloads implement the same high-level API and the same strings/DOM-style host calls, but intentionally preserve each language's normal ABI strategy.
- Hike uses linear memory plus generated JavaScript runtime glue. MoonBit `wasm-gc` uses host strings through WebAssembly GC / JS String Builtins, so its ABI is not pointer+length compatible with Hike. That difference is part of what this benchmark is measuring.
- `wasm-opt -Oz` rows are secondary post-link results. Compiler outputs are shown separately so compiler/toolchain behavior remains visible.
- This benchmark does **not** claim that one language is universally "stronger" from binary size alone.
{failures}

## Toolchain metadata

```text
{metadata}
```
"""
    args.markdown.write_text(md, encoding="utf-8")


if __name__ == "__main__":
    main()
