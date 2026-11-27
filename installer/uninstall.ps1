[CmdletBinding()]
param(
    [string]$Profile = 'desktop',
    [string]$DshCli = '',
    [string]$DshExe = '',
    [int]$DelaySeconds = 0,
    [string]$LogPath = '',
    [switch]$NoRestart,
    [switch]$DryRun,
    [switch]$SkipProcessStop
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'common.ps1')

Enable-Utf8Console


if (-not $LogPath) {
    $logDir = Get-InstallerLogDir
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $LogPath = Join-Path $logDir ("uninstall-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function Write-Step {
    param([string]$Text)
    Write-InstallerLog -LogPath $LogPath -Message $Text
}

Write-Step '=============================================='
Write-Step 'dsh-startup-screen 卸载器'
Write-Step '=============================================='

$dsh = Resolve-DshCli -Hint $DshCli -DshExeHint $DshExe
if (-not $dsh.Cli) {
    Write-Step '[X] 找不到 dsh CLI。请先打开一次 DSH 桌面端，或用 -DshCli 指定 dsh.cmd 的完整路径。'
    exit 1
}
if (-not $dsh.Exe) { $dsh.Exe = Resolve-DshExe -Cli $dsh.Cli -Hint $DshExe }
Write-Step ("dsh CLI：{0}" -f $dsh.Cli)

$profileDir = Get-DshProfileDir -Profile $Profile
Write-Step ("profile：{0}" -f $profileDir)
if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
    Write-Step ("[X] 找不到 profile 目录：{0}" -f $profileDir)
    exit 1
}

$installed = Get-InstalledVersion -ProfileDir $profileDir
if (-not $installed) {
    Write-Step '当前 profile 里没有 dsh-startup-screen，无需卸载。'
    exit 0
}
Write-Step ("当前已安装：{0}" -f $installed)

$running = @(Get-DshProcesses -DshExe $dsh.Exe)
if ($running.Count -gt 0) {
    Write-Step ("DSH 正在运行（{0} 个进程），卸载前会自动关闭。" -f $running.Count)
} else {
    Write-Step 'DSH 当前未运行。'
}

if ($DryRun) {
    Write-Step 'DryRun：只检查，不改动任何文件或进程。'
    Write-Step 'DRY-RUN OK'
    exit 0
}

if ($DelaySeconds -le 0) { $DelaySeconds = 5 }
if ($DelaySeconds -gt 0) {
    Write-Step ("{0} 秒后关闭 DSH 并开始卸载..." -f $DelaySeconds)
    Start-Sleep -Seconds $DelaySeconds
}

$wasRunning = @(Get-DshProcesses -DshExe $dsh.Exe).Count -gt 0
$stopped = $true
if ($SkipProcessStop) {
    Write-Step '跳过关闭 DSH（-SkipProcessStop）。'
} else {
    $stopped = Stop-DshForInstall -DshExe $dsh.Exe -LogPath $LogPath
    if (-not $stopped) {
        Write-Step '[X] 无法关闭 DSH。请手动完全退出 DSH（含托盘）后重试。'
        exit 1
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = ''
$ok = $false
$exitCode = 1

try {
    $backup = Backup-ProfileFiles -ProfileDir $profileDir -Stamp $stamp -LogPath $LogPath

    Write-Step ("执行：dsh plugin --profile {0} remove dsh-startup-screen" -f $Profile)
    $output = & $dsh.Cli plugin --profile $Profile remove dsh-startup-screen 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Step ([string]$line) }
    if ($code -ne 0) { throw ("dsh plugin remove 失败，退出码 {0}" -f $code) }

    $list = ''
    try { $list = (& $dsh.Cli plugin --profile $Profile list 2>&1 | Out-String) } catch { $list = '' }
    if ($list -match 'dsh-startup-screen@') {
        throw '卸载后 dsh plugin list 里仍能看到插件。'
    }
    Write-Step '已确认 profile 依赖里不再包含插件。'
    $ok = $true
    $exitCode = 0
} catch {
    Write-Step ('[X] 卸载失败：' + $_.Exception.Message)
    $exitCode = 1
} finally {
    if (-not $NoRestart) {
        if ($wasRunning -and -not $stopped) {
            Write-Step 'DSH 之前没有成功关闭，跳过自动启动，避免开出第二个实例。'
        } else {
            Start-DshApp -DshExe $dsh.Exe -LogPath $LogPath | Out-Null
        }
    } else {
        Write-Step '按参数要求不自动重启 DSH。'
    }
}

if ($ok) {
    Write-Host ''
    Write-Host '=============================================='
    Write-Host ' 卸载完成。'
    Write-Host (" 日志：{0}" -f $LogPath)
    if ($backup) { Write-Host (" 备份：{0}" -f $backup) }
    Write-Host ' 用户设置保留在 %USERPROFILE%\.dsh\dsh-startup.json（如不需要可手动删除）。'
    Write-Host '=============================================='
} else {
    Write-Host ''
    Write-Host '[X] 卸载未完成，请把上面的日志发给维护者。'
    Write-Host (" 日志：{0}" -f $LogPath)
    if ($backup) { Write-Host (" 备份：{0}" -f $backup) }
}

exit $exitCode