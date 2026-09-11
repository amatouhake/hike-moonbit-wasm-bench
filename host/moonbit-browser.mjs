/** Minimal browser host for the MoonBit wasm-gc benchmark.
 *
 * MoonBit's `use-js-builtin-string` link option exposes String as a JS string
 * across the Wasm boundary, so this host does not need a linear-memory UTF-8
 * decoder or allocator.
 */
export function getImports() {
  return {
    env: {
      js_log: (msg) => console.log(`[MoonBit Wasm] ${msg}`),
      js_set_text: (id, text) => {
        const el = document.getElementById(id);
        if (el) el.innerText = text;
      },
      js_append_text: (id, text) => {
        const el = document.getElementById(id);
        if (el) el.innerText += text;
      },
      js_set_badge_color: (id, color) => {
        const el = document.getElementById(id);
        if (el) el.style.backgroundColor = color;
      },
    },
  };
}

export async function loadMoonBitWasm(url) {
  const bytes = await fetch(url).then((response) => response.arrayBuffer());
  const { instance } = await WebAssembly.instantiate(bytes, getImports(), {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  return instance.exports;
}
