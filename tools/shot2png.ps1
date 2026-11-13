param(
  [Parameter(Mandatory=$true)][string]$In,
  [Parameter(Mandatory=$true)][string]$Out
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
try {
  Add-Type -AssemblyName System.Drawing
  $fs = [System.IO.File]::OpenRead($In)
  try {
    $head = New-Object byte[] 64
    $n = $fs.Read($head, 0, 64)
    if ($n -le 0) { throw "empty header" }
    $lf = [Array]::IndexOf($head, [byte]10)
    if ($lf -lt 0) { throw "missing LF in header" }
    $hdr = [System.Text.Encoding]::ASCII.GetString($head, 0, $lf)
    $parts = $hdr.Trim().Split(' ')
    if ($parts.Length -lt 4 -or $parts[0] -ne 'TSRAW') { throw "bad header: $hdr" }
    $w = [int]$parts[1]; $h = [int]$parts[2]; $fmt = $parts[3]
    if ($fmt -ne 'RGBA') { throw "bad fmt: $fmt" }
    $fs.Position = $lf + 1
    $need = $w * $h * 4
    $rgba = New-Object byte[] $need
    $off = 0
    while ($off -lt $need) {
      $n = $fs.Read($rgba, $off, $need - $off)
      if ($n -le 0) { throw "short read at $off/$need" }
      $off += $n
    }
  } finally { $fs.Close() }
  $bgra = New-Object byte[] $need
  for ($i = 0; $i -lt $need; $i += 4) {
    $bgra[$i] = $rgba[$i + 2]
    $bgra[$i + 1] = $rgba[$i + 1]
    $bgra[$i + 2] = $rgba[$i]
    $bgra[$i + 3] = $rgba[$i + 3]
  }
  $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
    try {
      [System.Runtime.InteropServices.Marshal]::Copy($bgra, 0, $data.Scan0, $need)
    } finally { $bmp.UnlockBits($data) }
    $outDir = [System.IO.Path]::GetDirectoryName($Out)
    if ($outDir -and !(Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $bmp.Dispose() }
  $bytes = (Get-Item $Out).Length
  Write-Output "SHOT2PNG ok in=$In out=$Out bytes=$bytes"
  exit 0
} catch {
  Write-Error "SHOT2PNG fail: $($_.Exception.Message)"
  exit 1
}
