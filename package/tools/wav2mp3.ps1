$ErrorActionPreference = 'Stop'

# WAV -> MP3 through Windows Media Foundation's MediaTranscoder.
# Windows PowerShell 5.1 only: PowerShell 7 dropped the WinRT projection.
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($task, $type) {
  $asTask = $asTaskGeneric.MakeGenericMethod($type)
  $netTask = $asTask.Invoke($null, @($task))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.MediaProperties.AudioEncodingQuality, Windows.Media.MediaProperties, ContentType = WindowsRuntime] | Out-Null

$inPath = $args[0]
$outPath = $args[1]
$dir = Split-Path -Parent $outPath
$name = Split-Path -Leaf $outPath

$inFile = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($inPath)) ([Windows.Storage.StorageFile])
$outFolder = Await ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($dir)) ([Windows.Storage.StorageFolder])
$outFile = Await ($outFolder.CreateFileAsync($name, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])

$profile = [Windows.Media.MediaProperties.MediaEncodingProfile]::CreateMp3([Windows.Media.MediaProperties.AudioEncodingQuality]::High)
$transcoder = New-Object Windows.Media.Transcoding.MediaTranscoder
$prep = Await ($transcoder.PrepareFileTranscodeAsync($inFile, $outFile, $profile)) ([Windows.Media.Transcoding.PrepareTranscodeResult])

if ($prep.CanTranscode) {
  # IAsyncAction handed back as a bare COM object defeats AsTask overload
  # resolution here, so fire it and wait for the output to stop growing.
  $null = $prep.TranscodeAsync()
  $last = -1
  for ($i = 0; $i -lt 900; $i++) {
    Start-Sleep -Milliseconds 100
    $len = if (Test-Path $outPath) { (Get-Item $outPath).Length } else { 0 }
    if ($len -gt 0 -and $len -eq $last) { break }
    $last = $len
  }
  Write-Output "OK $outPath ($last bytes)"
} else {
  Write-Output "FAILED reason=$($prep.FailureReason)"
}
