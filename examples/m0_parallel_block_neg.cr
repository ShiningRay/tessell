# M0-WP2 C1 negative evidence: `Parallel.new(name,size,&)` block form.
# This file is EXPECTED TO FAIL COMPILATION (compile-time API shape evidence only).
# Do not "fix" it; run `crystal build examples/m0_parallel_block_neg.cr` to capture the error.

par = Fiber::ExecutionContext::Parallel.new("w", 4) { }
par.spawn { }
