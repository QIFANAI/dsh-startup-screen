$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

$tools = $PSScriptRoot
$outDir = Join-Path $tools 'final-voice'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Get-ChildItem $outDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

$text = 'Welcome to use DeepSeek Harness.'
$voice = 'Microsoft Zira Desktop'

foreach ($rate in @(0, -1, -2)) {
  $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $synth.SelectVoice($voice)
  $synth.Rate = $rate
  $synth.Volume = 100
  $wav = Join-Path $outDir ("line-6-rate{0}.wav" -f $rate)
  $synth.SetOutputToWaveFile($wav)
  $synth.Speak($text)
  $synth.SetOutputToNull()
  $synth.Dispose()

  $mp3 = Join-Path $outDir ("line-6-rate{0}.mp3" -f $rate)
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'wav2mp3.ps1') $wav $mp3 | Out-Host
}
Write-Output "text: $text"
Get-ChildItem $outDir -Filter *.mp3 | Select-Object Name, Length | Format-Table -AutoSize
