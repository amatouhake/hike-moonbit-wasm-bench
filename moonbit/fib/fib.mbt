fn fib(n : Int) -> Int {
  if n <= 1 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

#export_name("RunComputation")
pub fn run_computation(n : Int) -> Int {
  fib(n)
}
