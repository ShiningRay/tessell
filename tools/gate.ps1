param(
  [string]$FailProbe = ""
)

$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$crystal = "C:\msys64\ucrt64\bin\crystal.exe"
$msysBin = "C:\msys64\ucrt64\bin"
$env:PATH = "$msysBin;$env:PATH"

Set-Location $repoRoot

$results = @()
$overallPass = $true

function Add-Result([string]$name, [string]$cmd, [int]$exitCode,
    [string]$token, [bool]$pass, [double]$ms) {
  $script:results += [PSCustomObject]@{
    Name = $name; Command = $cmd; ExitCode = $exitCode
    Token = $token; Pass = $pass; Ms = [math]::Round($ms, 1)
  }
  if (-not $pass) { $script:overallPass = $false }
  $mark = if ($pass) { "PASS" } else { "FAIL" }
  Write-Output "[$mark] $name exit=$exitCode ms=$([math]::Round($ms,1))"
  if ($token -ne "") { Write-Output "  token: $token" }
  Write-Output "  cmd: $cmd"
}

function Run-Crystal([string]$name, [string]$argLine, [scriptblock]$judge) {
  $cmd = "$crystal $argLine"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $out = & $crystal ($argLine -split ' ') 2>&1 | Out-String
  $code = $LASTEXITCODE
  $sw.Stop()
  $pass, $token = & $judge $out $code
  Add-Result $name $cmd $code $token $pass $sw.Elapsed.TotalMilliseconds
  return $out
}

# 1. crystal spec
$specCmd = "spec"
Run-Crystal "spec" $specCmd {
  param($out, $code)
  $m = [regex]::Match($out, '(\d+) examples?, (\d+) failures?')
  if ($m.Success) {
    $n = $m.Groups[1].Value; $f = $m.Groups[2].Value
    $tok = "$n examples, $f failures"
    $ok = ($code -eq 0 -and $f -eq "0")
    return @($ok, $tok)
  }
  return @($false, "parse_failed")
} | Out-Null

# 2. build src
$buildCmd = "build src/tessell.cr -o bin/gate_build.exe"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$buildOut = & $crystal build src/tessell.cr -o bin/gate_build.exe 2>&1 | Out-String
$buildCode = $LASTEXITCODE
if (Test-Path "bin/gate_build.exe") { Remove-Item "bin/gate_build.exe" -Force }
$sw.Stop()
$bTok = if ($buildOut.Trim() -eq "") { "ok" } else { ($buildOut -split "`n")[0].Trim() }
Add-Result "build_src" "$crystal $buildCmd" $buildCode $bTok `
  ($buildCode -eq 0) $sw.Elapsed.TotalMilliseconds

# 3. examples --verify
function Run-Example([string]$name, [string]$file, [string[]]$exArgs, [string[]]$need) {
  $argStr = ($exArgs -join ' ')
  $cmd = "$crystal run $file -- $argStr"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $allArgs = @('run', $file, '--') + $exArgs
  $out = & $crystal $allArgs 2>&1 | Out-String
  $code = $LASTEXITCODE
  $sw.Stop()
  $lines = $out -split "`r?`n"
  $tokLine = ""
  # prefer a line containing all needed tokens
  if ($need.Count -gt 0) {
    $hitNeed = $lines | Where-Object {
      $line = $_; ($need | Where-Object { $line -match [regex]::Escape($_) }).Count -eq $need.Count
    } | Select-Object -Last 1
    if ($hitNeed) { $tokLine = $hitNeed.Trim() }
    # else prefer last line containing the primary needed token
    if ($tokLine -eq "") {
      foreach ($n in $need) {
        $hitN = $lines | Where-Object { $_ -match [regex]::Escape($n) } | Select-Object -Last 1
        if ($hitN) { $tokLine = $hitN.Trim(); break }
      }
    }
  }
  if ($tokLine -eq "") {
    foreach ($p in @('emoji_pixel_match','pixel_match','verify=','diff_pixels','diff_A_vs_C','alloc_windows')) {
      $hit = $lines | Where-Object { $_ -match [regex]::Escape($p) } | Select-Object -Last 1
      if ($hit) { $tokLine = $hit.Trim(); break }
    }
  }
  if ($tokLine -eq "") { $tokLine = ($lines | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1) }
  $ok = ($code -eq 0)
  foreach ($n in $need) {
    if ($out -notmatch [regex]::Escape($n)) { $ok = $false }
  }
  Add-Result $name $cmd $code $tokLine $ok $sw.Elapsed.TotalMilliseconds
  return $out
}

Run-Example "ex_m2_text_verify" "examples/m2_text_window.cr" @("--verify") `
  @("pixel_match=true") | Out-Null
Run-Example "ex_m2_text_emoji_verify" "examples/m2_text_window.cr" `
  @("--emoji","--verify") @("emoji_pixel_match=true") | Out-Null
Run-Example "ex_m3_dirty_verify" "examples/m3_dirty_window.cr" @("--verify") `
  @("verify=pass","diff_pixels=","diff_A_vs_C=") | Out-Null
Run-Example "ex_m3_dpi_light" "examples/m3_dpi_theme.cr" `
  @("--dpi=1.5","--theme=light","--frames=20") @("verify=pass") | Out-Null
Run-Example "ex_m3_dpi_dark" "examples/m3_dpi_theme.cr" `
  @("--dpi=1.5","--theme=dark","--frames=20") @("verify=pass") | Out-Null
Run-Example "ex_m3_scroll_dy20" "examples/m3_scroll_window.cr" `
  @("--verify","--dy=20") @("verify=pass","diff_pixels=","diff_A_vs_C=","alloc_windows=") | Out-Null
Run-Example "ex_m3_scroll_dy600" "examples/m3_scroll_window.cr" `
  @("--verify","--dy=600") @("verify=pass","diff_pixels=","diff_A_vs_C=","alloc_windows=") | Out-Null
Run-Example "ex_m3_path_verify" "examples/m3_path_window.cr" `
  @("--verify","--frames=20") @("verify=pass","stencil_bits=","diff_pixels=0","fill_pixels_gl=","fill_pixels_cpu=") | Out-Null

# 4. zero_alloc_frame.cr
$zaCmd = "run tools/zero_alloc_frame.cr -- --frames=200 --json"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$zaOut = & $crystal run tools/zero_alloc_frame.cr -- --frames=200 --json 2>&1 | Out-String
$zaCode = $LASTEXITCODE
$sw.Stop()
$zaOkCount = ([regex]::Matches($zaOut, '"criterion_ok"\s*:\s*true')).Count
$zaFailCount = ([regex]::Matches($zaOut, '"criterion_ok"\s*:\s*false')).Count
$zaTok = "criterion_ok=true_count=$zaOkCount false_count=$zaFailCount"
$zaPass = ($zaCode -eq 0 -and $zaOkCount -ge 2 -and $zaFailCount -eq 0)
Add-Result "zero_alloc_frame" "$crystal $zaCmd" $zaCode $zaTok $zaPass $sw.Elapsed.TotalMilliseconds

# 5. bench_scroll.cr (record only, no assertion)
$bsCmd = "run tools/bench_scroll.cr"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bsOut = & $crystal run tools/bench_scroll.cr 2>&1 | Out-String
$bsCode = $LASTEXITCODE
$sw.Stop()
$bsLines = $bsOut -split "`r?`n"
$bsTok = ($bsLines | Where-Object { $_ -match 'scenario=' } | Select-Object -Last 1)
if (-not $bsTok) { $bsTok = ($bsLines | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1) }
if ($bsTok) { $bsTok = $bsTok.Trim() } else { $bsTok = "no_output" }
Write-Output "[BENCH] bench_scroll (本机基线, 仅记录不断言) exit=$bsCode"
Write-Output "  token: $bsTok"
Add-Result "bench_scroll" "$crystal $bsCmd" $bsCode ("本机基线: " + $bsTok) $true $sw.Elapsed.TotalMilliseconds

# 6. atlas_raster_verify.cr
$atCmd = "run tools/atlas_raster_verify.cr"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$atOut = & $crystal run tools/atlas_raster_verify.cr 2>&1 | Out-String
$atCode = $LASTEXITCODE
$sw.Stop()
$atTok = ($atOut -split "`r?`n" | Where-Object { $_ -match 'ATLAS_RASTER_VERIFY_EXIT' } | Select-Object -Last 1)
if (-not $atTok) { $atTok = ($atOut -split "`r?`n" | Where-Object { $_ -match 'ATLAS_RASTER_VERIFY_FAILED' } | Select-Object -Last 1) }
if (-not $atTok) { $atTok = "no_exit_token" } else { $atTok = $atTok.Trim() }
$atPass = ($atCode -eq 0 -and $atOut -match 'ATLAS_RASTER_VERIFY_EXIT=0' -and $atOut -notmatch 'ATLAS_RASTER_VERIFY_FAILED')
Add-Result "atlas_raster_verify" "$crystal $atCmd" $atCode $atTok $atPass $sw.Elapsed.TotalMilliseconds

# 7. package.ps1 + bare PATH verify
$pkgCmd = "powershell -ExecutionPolicy Bypass -File tools/package.ps1 -OutDir dist\gate"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$pkgOut = powershell -NoProfile -ExecutionPolicy Bypass -File tools/package.ps1 -OutDir dist\gate 2>&1 | Out-String
$pkgCode = $LASTEXITCODE
$pkgTok = ($pkgOut -split "`r?`n" | Where-Object { $_ -match 'PACKAGE_OK|PACKAGE_FAIL|dll_count' } | Select-Object -First 1)
$pkgPass = ($pkgCode -eq 0 -and $pkgOut -match 'PACKAGE_OK')
$bareTok = "skipped"
$bareCode = -1
if ($pkgPass) {
  $exePath = Join-Path $repoRoot "dist\gate\m3_dpi_theme.exe"
  if (Test-Path $exePath) {
    $bareOut = cmd /c "set PATH=C:\Windows\System32;C:\Windows && `"$exePath`" --dpi=1.0 --frames=10 --verify" 2>&1 | Out-String
    $bareCode = $LASTEXITCODE
    $bareLine = ($bareOut -split "`r?`n" | Where-Object { $_ -match 'verify=' } | Select-Object -Last 1)
    if ($bareLine) { $bareTok = $bareLine.Trim() } else { $bareTok = "no_verify_token" }
    $pkgPass = ($pkgPass -and $bareCode -eq 0 -and $bareOut -match 'verify=pass')
  } else {
    $pkgPass = $false
    $bareTok = "exe_not_found"
  }
}
$sw.Stop()
$fullTok = "$pkgTok | bare_exit=$bareCode | $bareTok"
Add-Result "package_bare_path" $pkgCmd $pkgCode $fullTok $pkgPass $sw.Elapsed.TotalMilliseconds

# 8. file hygiene (whitelist; parallel WIP tolerated, anything else FAILs per-path)
$hSw = [System.Diagnostics.Stopwatch]::StartNew()
$statusOut = git status --short 2>&1 | Out-String
$statusLines = @($statusOut -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
$allowedUntracked = @(
  'tools/gate.ps1',
  'docs/evidence/M4-WP4-gate.md',
  'examples/app_demo.cr',
  'docs/usage.md',
  'docs/evidence/M3-gate-r4.md',
  'examples/m3_path_window.cr',
  'spec/path_gl_spec.cr',
  'docs/evidence/M3-WP4-stencil-cover.md',
  'spec/polygon_spec.cr',
  'src/tessell/render/polygon.cr'
)
$unexpected = @()
$allowedSeen = @()
foreach ($ln in $statusLines) {
  $t = $ln.TrimEnd()
  $xy = if ($t.Length -ge 2) { $t.Substring(0,2) } else { $t }
  $rest = if ($t.Length -ge 3) { $t.Substring(3).Trim() } else { '' }
  if ($xy -eq '??') {
    $p = $rest.Trim('"') -replace '\\','/'
    if ($allowedUntracked -contains $p) { $allowedSeen += $p }
    else { $unexpected += $t; Write-Output "  hygiene-unexpected: $t" }
  } else {
    $unexpected += $t; Write-Output "  hygiene-unexpected: $t"
  }
}
$subj = git log -1 --format=%s HEAD 2>&1 | Out-String
$subj = $subj.TrimEnd("`r","`n")
$subjBytes = [System.Text.Encoding]::UTF8.GetBytes($subj)
$bomOk = $true
if ($subjBytes.Length -ge 3) {
  if ($subjBytes[0] -eq 239 -and $subjBytes[1] -eq 187 -and $subjBytes[2] -eq 191) { $bomOk = $false }
}
$first6 = ($subjBytes[0..([Math]::Min(5,$subjBytes.Length-1))] | ForEach-Object { $_.ToString() }) -join ' '
$uniqAllowed = @($allowedSeen | Select-Object -Unique)
$uniqUnexpected = @($unexpected | Select-Object -Unique)
$statusOk = ($uniqUnexpected.Count -eq 0 -and $bomOk)
$hTok = "status_ok=$statusOk allowed_untracked=[$($uniqAllowed -join ',')] unexpected=[$($uniqUnexpected -join ',')] subj_first6=[$first6]"
$hPass = $statusOk
$hSw.Stop()
Add-Result "file_hygiene" "git status --short; git log -1 --format=%s" 0 $hTok $hPass $hSw.Elapsed.TotalMilliseconds

# optional fail probe (for acceptance proof without changing repo files)
if ($FailProbe -ne "") {
  $fSw = [System.Diagnostics.Stopwatch]::StartNew()
  $fpExists = Test-Path $FailProbe
  $fpCode = 1
  $fpTok = "FailProbe='$FailProbe' exists=$fpExists (intentional failure trigger)"
  $fSw.Stop()
  Add-Result "fail_probe" "Test-Path '$FailProbe'" $fpCode $fpTok $false $fSw.Elapsed.TotalMilliseconds
}

# summary
Write-Output ""
Write-Output "===== GATE SUMMARY ====="
foreach ($r in $results) {
  $m = if ($r.Pass) { "PASS" } else { "FAIL" }
  Write-Output ("{0} | {1} | exit={2} | ms={3} | {4}" -f $m,$r.Name,$r.ExitCode,$r.Ms,$r.Token)
}
$gateResult = if ($overallPass) { "PASS" } else { "FAIL" }
Write-Output "GATE_RESULT=$gateResult"
if ($overallPass) { exit 0 } else { exit 1 }
