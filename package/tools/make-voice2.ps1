$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

$outDir = Join-Path $PSScriptRoot 'voice-candidates-2'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Get-ChildItem $outDir -Filter *.wav | Remove-Item -Force

$voice = 'Microsoft Zira Desktop'

$candidates = @(
  @{ id = 'A'; rate = 0; text = 'Identity verified. Session established. Welcome.' },
  @{ id = 'B'; rate = 2; text = 'Identity verified. Session established. Welcome.' },
  @{ id = 'C'; rate = 1; text = 'Verified. Session established. Welcome aboard.' },
  @{ id = 'D'; rate = 0; text = 'Access granted. Session established. Welcome aboard.' },
  @{ id = 'E'; rate = 2; text = 'Session established. Welcome aboard.' }
)

foreach ($c in $candidates) {
  $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $synth.SelectVoice($voice)
  $synth.Rate = $c.rate
  $synth.Volume = 100
  $path = Join-Path $outDir ("line-6-{0}.wav" -f $c.id)
  $synth.SetOutputToWaveFile($path)
  $synth.Speak($c.text)
  $synth.SetOutputToNull()
  $synth.Dispose()
  Write-Output ("[{0}] rate={1}  {2}" -f $c.id, $c.rate, $c.text)
}
Write-Output "written to $outDir"
