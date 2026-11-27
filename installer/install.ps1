[CmdletBinding()]
param(
    [string]$Profile = 'desktop',
    [string]$Package = '',
    [string]$DshCli = '',
    [string]$DshExe = '',
    [string]$DshHome = '',
    [int]$DelaySeconds = 0,
    [string]$LogPath = '',
    [switch]$FromAgent,
    [switch]$Worker,
    [switch]$NoRestart,
    [switch]$DryRun,
    [switch]$SkipProcessStop,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'common.ps1')

Enable-Utf8Console


if ($DshHome) { $env:DSH_HOME = $DshHome }

if (-not $LogPath) {
    $logDir = Get-InstallerLogDir
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $LogPath = Join-Path $logDir ("install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
} else {
    $parent = Split-Path -Parent $LogPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
}

function Write-Step {
    param([string]$Text)
    Write-InstallerLog -LogPath $LogPath -Message $Text
}

Write-Step '=============================================='
Write-Step 'dsh-startup-screen 一键安装器'
Write-Step '=============================================='

try {
    $packagePath = Get-LatestPackage -Root $Root -Package $Package
} catch {
    Write-Step ('[X] ' + $_.Exception.Message)
    exit 1
}
$packageVersion = Get-PackageVersionFromFile -Path $packagePath
Write-Step ("安装包：{0}" -f $packagePath)
if ($packageVersion) { Write-Step ("目标版本：{0}" -f $packageVersion) }

$dsh = Resolve-DshCli -Hint $DshCli -DshExeHint $DshExe
if (-not $dsh.Cli) {
    Write-Step '[X] 找不到 dsh CLI。请先打开一次 DSH 桌面端，再重新运行；或用 -DshCli 指定 dsh.cmd 的完整路径。'
    exit 1
}
if (-not $dsh.Exe) {
    $dsh.Exe = Resolve-DshExe -Cli $dsh.Cli -Hint $DshExe
}
Write-Step ("dsh CLI：{0}" -f $dsh.Cli)
if ($dsh.Exe) {
    Write-Step ("DSH：{0}" -f $dsh.Exe)
} else {
    Write-Step '警告：没找到 DeepSeek Harness.exe，安装后需要手动打开 DSH。'
}

$profileDir = Get-DshProfileDir -Profile $Profile
Write-Step ("profile：{0}" -f $profileDir)
if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
    Write-Step ("[X] 找不到 profile 目录：{0}" -f $profileDir)
    Write-Step '    请先打开一次 DSH 桌面端，让它自动创建 profile，然后完全退出再重试。'
    exit 1
}

$currentVersion = Get-InstalledVersion -ProfileDir $profileDir
if ($currentVersion) {
    Write-Step ("当前已安装：{0}" -f $currentVersion)
} else {
    Write-Step '当前未安装。'
}

$patchPath = Join-Path $profileDir 'cordis.patch.yml'
$duplicates = @(Find-DuplicateInsert -PatchPath $patchPath)
if ($duplicates.Count -gt 0) {
    Write-Step ("检测到 profile patch 里有 {0} 段重复注册，安装时会注释掉（原文件先备份）。" -f $duplicates.Count)
} else {
    Write-Step 'profile patch 未发现重复注册。'
}

$running = @(Get-DshProcesses -DshExe $dsh.Exe)
if ($running.Count -gt 0) {
    Write-Step ("DSH 正在运行（{0} 个进程），安装前会自动关闭。" -f $running.Count)
} else {
    Write-Step 'DSH 当前未运行。'
}

if ($DryRun) {
    Write-Step 'DryRun：只检查，不改动任何文件或进程。'
    Write-Step 'DRY-RUN OK'
    exit 0
}

if ($FromAgent -and -not $Worker) {
    $delay = $DelaySeconds
    if ($delay -le 0) { $delay = 20 }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }

    $launcherDir = Join-Path $env:TEMP 'dsh-startup-screen-installer'
    New-Item -ItemType Directory -Force -Path $launcherDir | Out-Null
    $launcherPath = Join-Path $launcherDir ("worker-{0}.ps1" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $launcherLines = New-Object System.Collections.Generic.List[string]
    $launcherLines.Add('# 由 dsh-startup-screen install.ps1 自动生成；计划任务只跑这个短脚本。')
    $launcherLines.Add('$ErrorActionPreference = ''Stop''')
    $launcherLines.Add('$params = @{')
    $launcherLines.Add('    Worker = $true')
    $launcherLines.Add('    Profile = ' + (ConvertTo-PsSingleQuoted $Profile))
    $launcherLines.Add('    Package = ' + (ConvertTo-PsSingleQuoted $packagePath))
    $launcherLines.Add('    DelaySeconds = ' + $delay)
    $launcherLines.Add('    LogPath = ' + (ConvertTo-PsSingleQuoted $LogPath))
    $launcherLines.Add('    DshHome = ' + (ConvertTo-PsSingleQuoted (Get-DshHomePath)))
    if ($dsh.Cli) { $launcherLines.Add('    DshCli = ' + (ConvertTo-PsSingleQuoted $dsh.Cli)) }
    if ($dsh.Exe) { $launcherLines.Add('    DshExe = ' + (ConvertTo-PsSingleQuoted $dsh.Exe)) }
    if ($NoRestart) { $launcherLines.Add('    NoRestart = $true') }
    if ($SkipProcessStop) { $launcherLines.Add('    SkipProcessStop = $true') }
    $launcherLines.Add('}')
    $launcherLines.Add('& ' + (ConvertTo-PsSingleQuoted $PSCommandPath) + ' @params')
    [IO.File]::WriteAllText($launcherPath, ($launcherLines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($true)))

    $commandLine = '"' + $psExe + '" -NoProfile -ExecutionPolicy Bypass -File "' + $launcherPath + '"'
    Write-Step ("安排后台安装：{0} 秒后开始。" -f $delay)
    Write-Step ("后台脚本：{0}" -f $launcherPath)

    $taskName = 'DSH-Startup-Screen-Install'
    $scheduled = $false
    try {
        $action = New-ScheduledTaskAction -Execute $psExe -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $launcherPath + '"')
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(2))
        try { $trigger.EndBoundary = ((Get-Date).AddHours(2)).ToString('yyyy-MM-ddTHH:mm:ss') } catch { }
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -StartWhenAvailable -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 30)
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'dsh-startup-screen 一键安装（完成后自动过期删除）' -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        $scheduled = $true
        Write-Step ("已创建计划任务 {0} 并立即运行。" -f $taskName)
    } catch {
        Write-Step ('计划任务启动失败：' + $_.Exception.Message)
    }

    if (-not $scheduled) {
        $created = $null
        try {
            $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $commandLine }
        } catch {
            Write-Step ('WMI 后台启动失败：' + $_.Exception.Message)
        }

        if ($created -and $created.ReturnValue -eq 0) {
            Write-Step ("后台进程已启动：PID {0}" -f $created.ProcessId)
        } else {
            Write-Step '改用 Start-Process 启动后台进程。'
            Start-Process -FilePath $psExe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $launcherPath + '"') -WindowStyle Hidden | Out-Null
        }
    }

    Write-Host ''
    Write-Host ("安装已排队：DSH 将在约 {0} 秒后自动关闭、安装并重新打开。" -f $delay)
    Write-Host ("日志：{0}" -f $LogPath)
    exit 0
}

if ($Worker -and $DelaySeconds -gt 0) {
    Write-Step ("后台安装将在 {0} 秒后开始..." -f $DelaySeconds)
    Start-Sleep -Seconds $DelaySeconds
}

if (-not $Worker -and $DelaySeconds -le 0) { $DelaySeconds = 5 }
if (-not $Worker -and $DelaySeconds -gt 0) {
    Write-Step ("{0} 秒后关闭 DSH 并开始安装..." -f $DelaySeconds)
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
$installOk = $false
$exitCode = 1

try {
    $backup = Backup-ProfileFiles -ProfileDir $profileDir -Stamp $stamp -LogPath $LogPath

    if ($duplicates.Count -gt 0) {
        Disable-DuplicateInsert -PatchPath $patchPath -Ranges $duplicates -LogPath $LogPath | Out-Null
    }

    Write-Step ("执行：dsh plugin --profile {0} add {1}" -f $Profile, $packagePath)
    $output = & $dsh.Cli plugin --profile $Profile add $packagePath 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($output)) { Write-Step ([string]$line) }
    if ($code -ne 0) {
        throw ("dsh plugin add 失败，退出码 {0}" -f $code)
    }
    Write-Step '安装命令执行完成。'

    $verifyOk = Test-Installation -Profile $Profile -ProfileDir $profileDir -DshCli $dsh.Cli -ExpectedVersion $packageVersion -LogPath $LogPath
    if (-not $verifyOk) {
        throw '安装后校验未通过。'
    }
    $installOk = $true
    $exitCode = 0
} catch {
    Write-Step ('[X] 安装失败：' + $_.Exception.Message)
    $exitCode = 1
} finally {
    if (-not $NoRestart) {
        if ($wasRunning -and -not $stopped) {
            Write-Step 'DSH 之前没有成功关闭，跳过自动启动，避免开出第二个实例。'
        } else {
            $started = Start-DshApp -DshExe $dsh.Exe -LogPath $LogPath
            if ($started -and $installOk) {
                Start-Sleep -Seconds 8
                $cordisPath = Join-Path $profileDir 'cordis.yml'
                if (Test-Path -LiteralPath $cordisPath -PathType Leaf) {
                    $cordisText = Get-Content -LiteralPath $cordisPath -Raw -Encoding UTF8
                    if ($cordisText -match 'dsh-startup-screen') {
                        Write-Step 'cordis.yml 已包含插件条目。'
                    } else {
                        Write-Step '提示：cordis.yml 暂时没有插件条目。DSH 首次启动后会自动生成；若设置页看不到，请再重启一次。'
                    }
                }
            }
        }
    } else {
        Write-Step '按参数要求不自动重启 DSH。'
    }
}

if ($installOk) {
    Write-Host ''
    Write-Host '=============================================='
    Write-Host (" 安装完成：dsh-startup-screen {0}" -f $packageVersion)
    Write-Host ' 打开 DSH → 设置 → 启动动画'
    Write-Host (" 日志：{0}" -f $LogPath)
    if ($backup) { Write-Host (" 备份：{0}" -f $backup) }
    Write-Host '=============================================='
} else {
    Write-Host ''
    Write-Host '[X] 安装未完成，请把上面的日志发给维护者。'
    Write-Host (" 日志：{0}" -f $LogPath)
    if ($backup) { Write-Host (" 备份：{0}" -f $backup) }
}

exit $exitCode