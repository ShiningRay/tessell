param(
  [string]$OutDir = "dist\tessell",
  [string]$Example = "examples/m3_dpi_theme.cr",
  [switch]$Bundle,
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$crystal = "C:\msys64\ucrt64\bin\crystal.exe"
$objdump = "C:\msys64\ucrt64\bin\objdump.exe"
$msysBin = "C:\msys64\ucrt64\bin"

function Fail([string]$msg) {
  Write-Error $msg
  exit 1
}

if (!(Test-Path $crystal)) { Fail "crystal not found: $crystal" }
if (!(Test-Path $objdump)) { Fail "objdump not found: $objdump" }

Push-Location $repoRoot
try {
  $examplePath = Join-Path $repoRoot $Example
  if (!(Test-Path $examplePath)) { Fail "example not found: $examplePath" }

  if ($Bundle -and [string]::IsNullOrWhiteSpace($Version)) {
    $shard = Join-Path $repoRoot "shard.yml"
    if (Test-Path $shard) {
      $m = Select-String -Path $shard -Pattern '^version:\s*(.+)$' | Select-Object -First 1
      if ($m) { $Version = $m.Matches[0].Groups[1].Value.Trim().Trim('"').Trim("'") }
    }
    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "dev" }
  }

  $outAbs = Join-Path $repoRoot $OutDir
  New-Item -ItemType Directory -Force -Path $outAbs | Out-Null

  $exeName = [IO.Path]::GetFileNameWithoutExtension($Example) + ".exe"
  $exeOut = Join-Path $outAbs $exeName
  $buildTmp = Join-Path $repoRoot ("bin\" + $exeName)

  New-Item -ItemType Directory -Force -Path (Split-Path $buildTmp) | Out-Null

  # Build (needs ucrt64 toolchain in PATH)
  $oldPath = $env:PATH
  $env:PATH = "$msysBin;$env:PATH"
  try {
    & $crystal build $examplePath -o $buildTmp
    if ($LASTEXITCODE -ne 0) { Fail "crystal build failed: $LASTEXITCODE" }
  } finally {
    $env:PATH = $oldPath
  }

  Copy-Item $buildTmp $exeOut -Force

  # Collect imported DLL names from exe
  $imports = & $objdump -p $exeOut | Select-String 'DLL Name' |
    ForEach-Object { ($_ -replace '^\s*DLL Name:\s*', '').Trim() } |
    Sort-Object -Unique

  # Transitive closure of non-system DLLs present in msys2 ucrt64 bin
  $sys = @(
    'kernel32.dll','user32.dll','gdi32.dll','advapi32.dll','ole32.dll',
    'shell32.dll','opengl32.dll','ntdll.dll','ws2_32.dll','msvcrt.dll',
    'bcryptprimitives.dll','secur32.dll','crypt32.dll','rpcrt4.dll',
    'imm32.dll','comdlg32.dll','dwmapi.dll','uxtheme.dll','comctl32.dll',
    'shlwapi.dll','winmm.dll','version.dll','setupapi.dll','cfgmgr32.dll'
  )
  $queue = [System.Collections.Generic.Queue[string]]::new()
  $seen = @{}
  $toCopy = @{}

  foreach ($d in $imports) {
    $dl = $d.ToLowerInvariant()
    if ($sys -contains $dl) { continue }
    if ($dl -like 'api-ms-win-*') { continue }
    $src = Join-Path $msysBin $d
    if (Test-Path $src) {
      if (-not $seen.ContainsKey($dl)) {
        $seen[$dl] = $true
        $queue.Enqueue($d)
        $toCopy[$dl] = $src
      }
    }
  }

  while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    $curPath = Join-Path $msysBin $cur
    if (!(Test-Path $curPath)) { continue }
    $deps = & $objdump -p $curPath | Select-String 'DLL Name' |
      ForEach-Object { ($_ -replace '^\s*DLL Name:\s*', '').Trim() }
    foreach ($dep in $deps) {
      $dl = $dep.ToLowerInvariant()
      if ($sys -contains $dl) { continue }
      if ($dl -like 'api-ms-win-*') { continue }
      if ($seen.ContainsKey($dl)) { continue }
      $src = Join-Path $msysBin $dep
      if (Test-Path $src) {
        $seen[$dl] = $true
        $queue.Enqueue($dep)
        $toCopy[$dl] = $src
      }
    }
  }

  foreach ($kv in $toCopy.GetEnumerator()) {
    Copy-Item $kv.Value (Join-Path $outAbs ([IO.Path]::GetFileName($kv.Value))) -Force
  }

  $runCmdPath = Join-Path $outAbs "run.cmd"
  $noticePath = Join-Path $outAbs "NOTICE.txt"
  if ($Bundle) {
    $runLines = @(
      '@echo off',
      ('"%~dp0' + $exeName + '" %*'),
      'exit /b %ERRORLEVEL%'
    )
    [IO.File]::WriteAllText($runCmdPath, ($runLines -join "`r`n") + "`r`n")

    $notice = @(
      "Tessell distribution bundle",
      "",
      "This package contains a sample executable and runtime DLLs only.",
      "Tessell itself is distributed as source code in the repository.",
      "",
      "Third-party runtime components (upstream license notices):",
      "- FreeType (libfreetype): FTL / GPLv2+ (dual license)",
      "- HarfBuzz (libharfbuzz): MIT",
      "- Boehm GC (libgc): MIT-like",
      "- msys2/ucrt64 runtime DLLs: licenses as provided by their upstream projects",
      "",
      "Fonts: this bundle does NOT distribute any Windows system fonts.",
      "At runtime the sample loads fonts installed on the user's machine.",
      "See repository evidence: docs/evidence/M4-WP2-licensing.md"
    )
    [IO.File]::WriteAllText($noticePath, ($notice -join "`r`n") + "`r`n")
  } else {
    Remove-Item $runCmdPath -ErrorAction SilentlyContinue
    Remove-Item $noticePath -ErrorAction SilentlyContinue
  }

  # MANIFEST.txt: name, bytes, SHA256
  $manifestPath = Join-Path $outAbs "MANIFEST.txt"
  $lines = @()
  $files = Get-ChildItem -File $outAbs | Where-Object { $_.Name -ne "MANIFEST.txt" } |
    Sort-Object Name
  foreach ($f in $files) {
    $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $lines += ("{0}`t{1}`t{2}" -f $f.Name, $f.Length, $hash)
  }
  [IO.File]::WriteAllText($manifestPath, ($lines -join "`n") + "`n")

  Write-Output "PACKAGE_OK out_dir=$outAbs"
  Write-Output "exe=$exeName"
  Write-Output ("dll_count=" + $toCopy.Count)
  Write-Output "manifest=MANIFEST.txt"
  Write-Output "files:"
  Get-ChildItem -File $outAbs | Sort-Object Name | ForEach-Object {
    Write-Output ("  " + $_.Name + " " + $_.Length)
  }

  if ($Bundle) {
    $zipName = "tessell-$Version-win64.zip"
    $zipPath = Join-Path $repoRoot ("dist\" + $zipName)
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($outAbs, $zipPath)
    $zipInfo = Get-Item $zipPath
    $zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try { $entries = $zip.Entries.Count } finally { $zip.Dispose() }
    $exeBytes = (Get-Item $exeOut).Length
    Write-Output ("BUNDLE_OK zip=$zipPath zip_bytes=$($zipInfo.Length) entries=$entries dll_count=$($toCopy.Count) exe_bytes=$exeBytes sha256_zip=$zipHash")
  }

  exit 0
} catch {
  Write-Error $_
  exit 1
} finally {
  Pop-Location
}
