$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

$outDir = Join-Path $PSScriptRoot 'voice-candidates'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Same voice the plugin's browser-TTS path would pick: female, en-US.
$voice = 'Microsoft Zira Desktop'

$candidates = @(
  @{ id = 'A'; rate = -2; text = 'Identity verified. Session established. Welcome aboard.' },
  @{ id = 'B'; rate = -2; text = 'Access granted. Identity verified. Session established. Welcome.' },
  @{ id = 'C'; rate = -3; text = 'Verification complete. Session established. Welcome to DeepSeek Harness.' },
  @{ id = 'D'; rate = -2; text = 'Access granted. Your identity is verified. Session zero-zero-eight-seven is now active. Welcome.' }
)

foreach ($c in $candidates) {
  $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
  $synth.SelectVoice($voice)
  $synth.Rate = $c.rate
  $synth.Volume = 100
  $path = Join-Path $outDir ("line-6-candidate-{0}.wav" -f $c.id)
  $synth.SetOutputToWaveFile($path)
  $synth.Speak($c.text)
  $synth.SetOutputToNull()
  $synth.Dispose()
  $info = Get-Item $path
  $fs = [System.IO.File]::OpenRead($path)
  $br = New-Object System.IO.BinaryReader($fs)
  $fs.Seek(24, 'Begin') | Out-Null
  $rate = $br.ReadInt32()
  $br.ReadInt16() | Out-Null
  $br.ReadInt16() | Out-Null
  $br.ReadInt32() | Out-Null
  $dataLen = $br.ReadInt32()
  $br.Close()
  $secs = [math]::Round($dataLen / $rate / 2, 2)
  Write-Output ("[{0}] rate={1} {2,6:N0} bytes  ~{3}s  {4}" -f $c.id, $c.rate, $info.Length, $secs, $c.text)
}
