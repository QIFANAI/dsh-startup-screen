$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
$src = Join-Path $tools 'voice-candidates-2'
$dst = Join-Path $tools 'mp3-candidates'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem $dst -Filter *.mp3 -ErrorAction SilentlyContinue | Remove-Item -Force

foreach ($wav in Get-ChildItem $src -Filter *.wav | Sort-Object Name) {
  $out = Join-Path $dst ($wav.BaseName + '.mp3')
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'wav2mp3.ps1') $wav.FullName $out | Out-Host
}
Write-Output '--- result ---'
Get-ChildItem $dst -Filter *.mp3 | Select-Object Name, Length | Format-Table -AutoSize
