# Run M0-WP5m frame-time benchmark 3 times and report median of p50/p95/p99 (and alloc_bytes).
# Usage (from repo root, with ucrt64 Crystal on PATH or via full path):
#   $env:PATH="C:\msys64\ucrt64\bin;"+$env:PATH
#   pwsh -File tools/bench_frame_time.ps1                 # default scenario (alloc-heavy, NOT zero-alloc criterion)
#   pwsh -File tools/bench_frame_time.ps1 -Steady         # steady scenario (preallocated, M1-WP5 zero-alloc criterion)
#
# Why median-of-3: reduces single-run OS/timer/thermal/cache noise while keeping cost low;
# we do not average to avoid outlier skew. Report all 3 runs plus median per metric.
# Scenario note: default scenario intentionally allocates per frame; **MUST NOT** be used as M1-WP5
# "steady-state alloc delta == 0" criterion. Use -Steady for zero-allocation protocol evidence.
param(
  [switch]$Steady
)

$ErrorActionPreference = "Stop"
$crystal = "C:\msys64\ucrt64\bin\crystal.exe"
$bench = "tools/bench_frame_time.cr"
$runs = @()
$steadyArg = @()
if ($Steady) { $steadyArg = @("--steady") }

for ($i = 1; $i -le 3; $i++) {
  $out = & $crystal run $bench -- --frames=300 --warmup=30 @steadyArg 2>&1
  $exit = $LASTEXITCODE
  Write-Output "--- run $i exit=$exit ---"
  $out | ForEach-Object { Write-Output $_ }
  if ($exit -ne 0) { throw "run $i failed with exit=$exit" }
  $text = ($out | Out-String)
  $obj = [ordered]@{}
  foreach ($k in @("scenario","frames","warmup","p50_us","p95_us","p99_us","mean_us","min_us","max_us","alloc_bytes","alloc_bytes_steady","alloc_delta_zero","gc_disabled","gc_stable_start")) {
    if ($text -match "(?m)^${k}=(.+)$") { $obj[$k] = $Matches[1].Trim() }
  }
  $runs += [pscustomobject]$obj
}

function Median([double[]]$vals) {
  $s = $vals | Sort-Object
  $n = $s.Count
  if ($n -eq 0) { return 0 }
  $mid = [int][math]::Floor($n/2)
  if ($n % 2 -eq 1) { return $s[$mid] } else { return ($s[$mid-1] + $s[$mid]) / 2.0 }
}

$med = [ordered]@{
  p50_us = Median ($runs | ForEach-Object { [double]$_.p50_us })
  p95_us = Median ($runs | ForEach-Object { [double]$_.p95_us })
  p99_us = Median ($runs | ForEach-Object { [double]$_.p99_us })
  alloc_bytes = Median ($runs | ForEach-Object { [double]$_.alloc_bytes })
}
Write-Output "--- median-of-3 ---"
if ($runs.Count -gt 0 -and $runs[0].scenario) { Write-Output ("scenario={0}" -f $runs[0].scenario) }
Write-Output ("p50_us_median={0}" -f $med.p50_us)
Write-Output ("p95_us_median={0}" -f $med.p95_us)
Write-Output ("p99_us_median={0}" -f $med.p99_us)
Write-Output ("alloc_bytes_median={0}" -f $med.alloc_bytes)
if ($Steady) {
  $steadyAlloc = Median ($runs | ForEach-Object { [double]$_.alloc_bytes_steady })
  $allZero = ($runs | Where-Object { $_.alloc_delta_zero -ne "true" }).Count -eq 0
  Write-Output ("alloc_bytes_steady_median={0}" -f $steadyAlloc)
  Write-Output ("alloc_delta_zero_all={0}" -f $allZero)
}
