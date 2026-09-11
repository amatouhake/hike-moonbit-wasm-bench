#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/bench.env"

WORK="$ROOT/.work"
OUT="$ROOT/out"
RESULTS="$ROOT/results"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT" "$RESULTS"

say() { printf '\n==> %s\n' "$*"; }

save_runtime() {
  local dest="$1"
  if [[ -f "$OUT/runtime.js" ]]; then
    mv "$OUT/runtime.js" "$dest"
  else
    echo "expected Hike runtime.js was not generated" >&2
    exit 1
  fi
}

build_hike() {
  local commit="$1"
  local source="$2"
  local wasm_out="$3"
  local runtime_out="$4"

  git -C "$WORK/hike-lang" checkout --quiet "$commit"
  (
    cd "$WORK/hike-lang"
    go run ./cmd/hikec build -target wasm32 "$source" -o "$wasm_out"
  )
  save_runtime "$runtime_out"
}

copy_moonbit_output() {
  local target="$1"
  local pkg="$2"
  local dest="$3"
  local found

  found="$(find "$ROOT/moonbit/_build/$target/release/build" -type f -path "*/$pkg/$pkg.wasm" -print -quit 2>/dev/null || true)"
  if [[ -z "$found" ]]; then
    echo "could not locate MoonBit output for target=$target package=$pkg" >&2
    find "$ROOT/moonbit/_build" -type f -name '*.wasm' -print >&2 || true
    exit 1
  fi
  cp "$found" "$dest"
}

say "Tool versions"
moon version --all || moon version
printf 'go: '; go version
printf 'clang: '; clang --version | head -n 1
printf 'wasm-opt: '; wasm-opt --version || true
printf 'brotli: '; brotli --version || true

say "Clone Hike"
git clone --quiet https://github.com/kanryu/hike-lang.git "$WORK/hike-lang"

say "Build Hike Fibonacci at article-era commit"
build_hike \
  "$HIKE_ARTICLE_COMMIT" \
  "$ROOT/hike/fib.hike" \
  "$OUT/hike-fib-article.wasm" \
  "$OUT/hike-fib-article.runtime.js"

say "Build upstream Hike browser example at article-era commit"
build_hike \
  "$HIKE_ARTICLE_COMMIT" \
  "$WORK/hike-lang/examples/browser/main.hike" \
  "$OUT/hike-browser-article.wasm" \
  "$OUT/hike-browser-article.runtime.js"

say "Build upstream Hike browser example at latest pinned snapshot (non-blocking)"
git -C "$WORK/hike-lang" checkout --quiet "$HIKE_LATEST_SNAPSHOT"
set +e
(
  cd "$WORK/hike-lang"
  go run ./cmd/hikec build -target wasm32 \
    "$WORK/hike-lang/examples/browser/main.hike" \
    -o "$OUT/hike-browser-latest.wasm"
) >"$WORK/hike-latest-build.log" 2>&1
latest_status=$?
set -e
if [[ $latest_status -eq 0 ]]; then
  cat "$WORK/hike-latest-build.log"
  save_runtime "$OUT/hike-browser-latest.runtime.js"
else
  cat "$WORK/hike-latest-build.log" >&2
  {
    echo "Hike latest snapshot failed to build (exit=$latest_status)."
    echo "commit=$HIKE_LATEST_SNAPSHOT"
    echo
    cat "$WORK/hike-latest-build.log"
  } > "$OUT/hike-browser-latest.ERROR.txt"
  rm -f "$OUT/hike-browser-latest.wasm" "$OUT/runtime.js"
fi

say "Build MoonBit Fibonacci with linear-memory wasm backend"
(
  cd "$ROOT/moonbit"
  rm -rf _build
  moon build --target wasm --release --strip
)
copy_moonbit_output wasm fib "$OUT/moonbit-fib-wasm.wasm"

say "Build MoonBit Fibonacci + browser-equivalent sample with wasm-gc backend"
(
  cd "$ROOT/moonbit"
  rm -rf _build
  moon build --target wasm-gc --release --strip
)
copy_moonbit_output wasm-gc fib "$OUT/moonbit-fib-wasm-gc.wasm"
copy_moonbit_output wasm-gc browser "$OUT/moonbit-browser-wasm-gc.wasm"
cp "$ROOT/host/moonbit-browser.mjs" "$OUT/moonbit-browser-host.mjs"

say "Optimize wasm modules with Binaryen -Oz"
for wasm in "$OUT"/*.wasm; do
  [[ "$wasm" == *.oz.wasm ]] && continue
  oz="${wasm%.wasm}.oz.wasm"
  if wasm-opt --all-features -Oz "$wasm" -o "$oz" 2>"$WORK/wasm-opt.err"; then
    printf 'optimized %s\n' "$(basename "$wasm")"
  elif wasm-opt -Oz "$wasm" -o "$oz" 2>"$WORK/wasm-opt.err"; then
    printf 'optimized %s (without --all-features)\n' "$(basename "$wasm")"
  else
    printf 'warning: wasm-opt could not optimize %s: %s\n' \
      "$(basename "$wasm")" "$(tr '\n' ' ' < "$WORK/wasm-opt.err")" >&2
    rm -f "$oz"
  fi
done

say "Write reproducibility metadata"
{
  echo "generated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "hike_article_commit=$HIKE_ARTICLE_COMMIT"
  echo "hike_latest_snapshot=$HIKE_LATEST_SNAPSHOT"
  printf 'moon_version='; (moon version --all || moon version) | tr '\n' ';'; echo
  printf 'go_version='; go version
  printf 'clang_version='; clang --version | head -n 1
  printf 'wasm_opt_version='; wasm-opt --version || true
  printf 'brotli_version='; brotli --version || true
} > "$OUT/metadata.txt"

say "Measure raw + compressed sizes"
python3 "$ROOT/scripts/measure.py" \
  --out "$OUT" \
  --csv "$RESULTS/latest.csv" \
  --markdown "$RESULTS/latest.md" \
  --metadata "$OUT/metadata.txt"

printf '\nResults:\n'
cat "$RESULTS/latest.md"
