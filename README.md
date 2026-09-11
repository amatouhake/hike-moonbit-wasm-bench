# Hike vs MoonBit: WebAssembly size benchmark

A reproducible benchmark created to answer a narrow question raised by the Qiita article **「世界最強？ 2.56KBのWasmを吐くGo風言語 Hike」**: how does Hike's small WebAssembly output compare with modern MoonBit when the workload is held as close as practical?

Source article: <https://qiita.com/kanryu/items/95147e22ed5ac542ba58>

This repository deliberately separates two comparisons:

1. **Fib** — a small, strict compiler-output comparison that both Hike and MoonBit can express with a simple exported integer function.
2. **Browser-like API** — the Hike article's DOM/JS-style sample versus an equivalent MoonBit `wasm-gc` sample with the same exported operations, strings, Fibonacci computation, and four host calls.

## Why GitHub Actions?

The original investigation ran in a sandbox that could inspect GitHub but could not download the MoonBit toolchain or npm packages. GitHub Actions has ordinary network access, so the workflow installs the official MoonBit toolchain, checks out pinned Hike revisions, compiles every sample, runs Binaryen `wasm-opt -Oz`, and records exact byte sizes.

No benchmark numbers are handwritten. `results/latest.md` and `results/latest.csv` are generated from the actual artifacts.

## Source pins

Hike revisions are in [`bench.env`](./bench.env):

- `HIKE_ARTICLE_COMMIT`: article-era Hike snapshot used for the primary Hike comparison.
- `HIKE_LATEST_SNAPSHOT`: a pinned current snapshot, so later Hike changes do not silently rewrite historical results.

The browser Hike build uses Hike's own upstream `examples/browser/main.hike` at those revisions. The small Fib workload is in [`hike/fib.hike`](./hike/fib.hike).

MoonBit is installed from the official stable installer on every run. The exact `moon version --all` output is captured in the generated metadata so the result records the actual compiler/build-system version used.

## Workloads

### Fibonacci

Each implementation exports one recursive `Fib`-style computation. The benchmark builds:

- Hike `wasm32`
- MoonBit `wasm` (linear memory backend)
- MoonBit `wasm-gc`

This is the cleanest comparison for raw compiler output size.

### Browser-like workload

The Hike source is the article-era upstream browser example. The MoonBit version mirrors its observable API:

- `InitApp`
- `AddNumbers`
- `RunComputation`
- `AppendLogMessage`
- recursive Fibonacci
- the same UI strings
- four host calls corresponding to log / set text / append text / badge color

The ABI is intentionally idiomatic rather than artificially forced to match:

- **Hike:** linear memory, pointer+length strings, generated `runtime.js`
- **MoonBit wasm-gc:** WebAssembly GC / JS String Builtins, direct host strings, minimal JS import object

That is why both `.wasm`-only size and **Wasm + required JS glue** are reported.

## Measurements

For every `.wasm` artifact the workflow reports:

- raw bytes
- gzip level 9
- Brotli quality 11
- a secondary `wasm-opt -Oz` result when Binaryen can process the module

For browser workloads it also reports delivery payload size including the corresponding JavaScript glue.

See [`results/latest.md`](./results/latest.md) after a successful workflow run.

## Reproduce locally

On Linux with Go, Clang/lld, Git, Python, Binaryen, Brotli, and MoonBit installed:

```bash
bash scripts/benchmark.sh
```

GitHub Actions performs the same command in a clean `ubuntu-latest` runner.

## Caveats

Binary size is only one property. Runtime performance, startup, browser support, GC behavior, JS boundary costs, debugging, ecosystem maturity, and feature set can matter more in real applications. The purpose here is to replace a vague size comparison with reproducible artifacts and clearly stated conditions.
