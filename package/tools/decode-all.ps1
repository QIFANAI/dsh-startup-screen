$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$assets = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\assets'
$out = Join-Path $tools '_decoded'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -File -ErrorAction SilentlyContinue | Remove-Item -Force

foreach ($f in Get-ChildItem $assets -Filter 'line-*.mp3' | Sort-Object Name) {
  $dest = Join-Path $out ($f.BaseName + '.wav')
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'decode-to-wav.ps1') $f.FullName $dest | Out-Host
}
Write-Output '--- decoded ---'
Get-ChildItem $out -Filter *.wav | Select-Object Name, Length | Format-Table -AutoSize
