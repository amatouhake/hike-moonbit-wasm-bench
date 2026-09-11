fn js_log(msg : String) -> Unit = "env" "js_log"
fn js_set_text(id : String, text : String) -> Unit = "env" "js_set_text"
fn js_append_text(id : String, text : String) -> Unit = "env" "js_append_text"
fn js_set_badge_color(id : String, color : String) -> Unit = "env" "js_set_badge_color"

fn fib(n : Int) -> Int {
  if n <= 1 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

#export_name("InitApp")
pub fn init_app() -> Unit {
  js_log("Hike WebAssembly core initialized successfully.")
  js_set_text("status-badge", "Running (Wasm Active)")
  js_set_badge_color("status-badge", "#10b981")
  js_set_text(
    "wasm-output",
    "Hike Language Wasm Runtime is online.\nClick the buttons below to trigger native computations.",
  )
}

#export_name("AddNumbers")
pub fn add_numbers(a : Int, b : Int) -> Int {
  a + b
}

#export_name("RunComputation")
pub fn run_computation(n : Int) -> Int {
  js_log("Executing RunComputation inside WebAssembly...")
  fib(n)
}

#export_name("AppendLogMessage")
pub fn append_log_message(msg_code : Int) -> Unit {
  if msg_code == 1 {
    js_append_text(
      "wasm-log-box",
      "\n[Wasm Event] User clicked Action A: Memory layout validated.",
    )
  } else if msg_code == 2 {
    js_append_text(
      "wasm-log-box",
      "\n[Wasm Event] User clicked Action B: Slice buffer manipulation complete.",
    )
  } else {
    js_append_text(
      "wasm-log-box",
      "\n[Wasm Event] Heartbeat tick received from browser.",
    )
  }
}
