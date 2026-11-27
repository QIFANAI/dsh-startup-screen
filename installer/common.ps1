# dsh-startup-screen 安装器共用函数
# 兼容 Windows PowerShell 5.1；所有路径统一转为绝对路径。

$script:InstallerUtf8 = New-Object System.Text.UTF8Encoding($false)

function Enable-Utf8Console {
    # dsh CLI 输出 UTF-8；PowerShell 5.1 默认按 OEM 代码页解码，会显示乱码。
    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $encoding
        $global:OutputEncoding = $encoding
    } catch { }
}

function Write-InstallerLog {
    param(
        [string]$LogPath,
        [string]$Message
    )
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line
    if ($LogPath) {
        try {
            [IO.File]::AppendAllText($LogPath, $line + "`r`n", $script:InstallerUtf8)
        } catch {
            # 日志写不进去不应影响安装
        }
    }
}

function ConvertTo-PsSingleQuoted {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-InstallerLogDir {
    # 日志放 %TEMP%：%LOCALAPPDATA% 下的目录可能带 EFS 加密，计划任务读不到。
    $base = $env:TEMP
    if (-not $base) { $base = $env:LOCALAPPDATA }
    return (Join-Path $base 'dsh-startup-screen-installer\logs')
}

function Get-DshHomePath {
    if ($env:DSH_HOME -and $env:DSH_HOME.Trim().Length -gt 0) {
        return [IO.Path]::GetFullPath($env:DSH_HOME)
    }
    return [IO.Path]::GetFullPath((Join-Path $HOME '.dsh'))
}

function Get-DshProfileDir {
    param([string]$Profile)
    return [IO.Path]::GetFullPath((Join-Path (Get-DshHomePath) ('profiles\' + $Profile)))
}

function Get-DshCmdLines {
    if ($null -eq $script:DshCmdLines) { $script:DshCmdLines = @{} }
    if ($null -eq $script:DshCmdLinesAt) { $script:DshCmdLinesAt = [DateTime]::MinValue }
    $age = ((Get-Date) - $script:DshCmdLinesAt).TotalSeconds
    if ($script:DshCmdLines.Count -gt 0 -and $age -lt 3) { return $script:DshCmdLines }

    $map = @{}
    try {
        foreach ($item in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
            try { $map[[int]$item.ProcessId] = [string]$item.CommandLine } catch { }
        }
    } catch { }
    $script:DshCmdLines = $map
    $script:DshCmdLinesAt = Get-Date
    return $map
}

function Test-DshAppProcess {
    param(
        [int]$Id,
        [hashtable]$CmdLines
    )
    $cmd = $null
    if ($CmdLines -and $CmdLines.ContainsKey($Id)) { $cmd = $CmdLines[$Id] }
    if ($cmd) {
        # dsh CLI 也是 DeepSeek Harness.exe（ELECTRON_RUN_AS_NODE），不能当成桌面端关掉。
        if ($cmd -match '\\cli\.js' -or $cmd -match '--expose-internals') { return $false }
    }
    return $true
}

function Get-DshProcesses {
    param([string]$DshExe)

    $all = @(Get-Process -ErrorAction SilentlyContinue)
    $cmdLines = Get-DshCmdLines
    if ($DshExe) {
        $full = [IO.Path]::GetFullPath($DshExe)
        $matched = @($all | Where-Object {
            $path = $null
            try { $path = $_.Path } catch { }
            if (-not $path) { return $false }
            try {
                if ([IO.Path]::GetFullPath($path) -ine $full) { return $false }
            } catch { return $false }
            return (Test-DshAppProcess -Id $_.Id -CmdLines $cmdLines)
        })
        if ($matched.Count -gt 0) { return $matched }

        # 路径读不到的进程只按进程名兜底，避免误杀另一个安装位置的 DSH。
        return @($all | Where-Object {
            $path = $null
            try { $path = $_.Path } catch { }
            if ($path) { return $false }
            if ($_.ProcessName -ine 'DeepSeek Harness') { return $false }
            return (Test-DshAppProcess -Id $_.Id -CmdLines $cmdLines)
        })
    }

    return @($all | Where-Object {
        if ($_.ProcessName -ine 'DeepSeek Harness') { return $false }
        return (Test-DshAppProcess -Id $_.Id -CmdLines $cmdLines)
    })
}

function Get-RegistryDshDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
        $items = @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            $name = [string]$item.DisplayName
            if ($name -notmatch 'DeepSeek\s*Harness') { continue }
            if ($item.InstallLocation) {
                $dirs.Add([string]$item.InstallLocation)
            }
            if ($item.DisplayIcon) {
                $icon = [string]$item.DisplayIcon
                $icon = $icon -replace ',\s*-?\d+\s*$', ''
                $icon = $icon.Trim('"')
                if ($icon -match '\.exe$') {
                    $dirs.Add((Split-Path -Parent $icon))
                }
            }
        }
    }
    return $dirs
}

function Get-ShortcutDshExes {
    $exes = New-Object System.Collections.Generic.List[string]
    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:USERPROFILE 'Desktop')
    )
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { }
    if (-not $shell) { return $exes }

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $links = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'DeepSeek|Harness|DSH' })
        foreach ($link in $links) {
            try {
                $target = $shell.CreateShortcut($link.FullName).TargetPath
                if ($target -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                    $exes.Add([IO.Path]::GetFullPath($target))
                }
            } catch { }
        }
    }
    return $exes
}

function Get-CommonDshDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    $local = $env:LOCALAPPDATA
    $programs = $null
    if ($local) {
        $programs = Join-Path $local 'Programs'
        $dirs.Add((Join-Path $local 'Programs\DeepSeek Harness'))
        $dirs.Add((Join-Path $local 'Programs\dsh'))
        $dirs.Add((Join-Path $local 'Programs\deepseek-harness'))
        $dirs.Add((Join-Path $local 'DeepSeek Harness'))
    }
    if ($env:ProgramFiles) {
        $dirs.Add((Join-Path $env:ProgramFiles 'DeepSeek Harness'))
    }
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) {
        $dirs.Add((Join-Path $pf86 'DeepSeek Harness'))
    }
    $dirs.Add('C:\dsh')
    $dirs.Add('D:\dsh')
    $dirs.Add('E:\dsh')

    if ($programs -and (Test-Path -LiteralPath $programs)) {
        $subs = @(Get-ChildItem -LiteralPath $programs -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'dsh|DeepSeek|Harness' })
        foreach ($sub in $subs) { $dirs.Add($sub.FullName) }
    }

    $existing = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $dirs) {
        if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
            $existing.Add([IO.Path]::GetFullPath($dir))
        }
    }
    return $existing
}

function Get-InstallDirFromCli {
    param([string]$Cli)
    if (-not $Cli) { return $null }
    $bin = Split-Path -Parent $Cli
    $cliDir = Split-Path -Parent $bin
    $runtime = Split-Path -Parent $cliDir
    $resources = Split-Path -Parent $runtime
    return [IO.Path]::GetFullPath((Split-Path -Parent $resources))
}

function Resolve-DshExe {
    param(
        [string]$Cli,
        [string]$Hint
    )
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Hint) { $candidates.Add($Hint) }

    if ($Cli) {
        $installDir = Get-InstallDirFromCli -Cli $Cli
        if ($installDir) { $candidates.Add((Join-Path $installDir 'DeepSeek Harness.exe')) }
    }

    foreach ($proc in @(Get-DshProcesses -DshExe $null)) {
        if ($proc.Path -and ((Split-Path -Leaf $proc.Path) -ieq 'DeepSeek Harness.exe')) {
            $candidates.Add($proc.Path)
        }
    }
    foreach ($exe in @(Get-ShortcutDshExes)) { $candidates.Add($exe) }
    foreach ($dir in @(Get-RegistryDshDirs)) { $candidates.Add((Join-Path $dir 'DeepSeek Harness.exe')) }
    foreach ($dir in @(Get-CommonDshDirs)) { $candidates.Add((Join-Path $dir 'DeepSeek Harness.exe')) }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Resolve-DshCli {
    param(
        [string]$Hint,
        [string]$DshExeHint
    )
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Hint) { $candidates.Add($Hint) }

    $command = Get-Command dsh -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { $candidates.Add($command.Source) }

    if ($DshExeHint) {
        $dir = Split-Path -Parent $DshExeHint
        if ($dir) { $candidates.Add((Join-Path $dir 'resources\runtime\cli\bin\dsh.cmd')) }
    }

    foreach ($proc in @(Get-DshProcesses -DshExe $DshExeHint)) {
        if ($proc.Path) {
            $dir = Split-Path -Parent $proc.Path
            $candidates.Add((Join-Path $dir 'resources\runtime\cli\bin\dsh.cmd'))
        }
    }
    foreach ($dir in @(Get-RegistryDshDirs)) { $candidates.Add((Join-Path $dir 'resources\runtime\cli\bin\dsh.cmd')) }
    foreach ($exe in @(Get-ShortcutDshExes)) {
        $dir = Split-Path -Parent $exe
        $candidates.Add((Join-Path $dir 'resources\runtime\cli\bin\dsh.cmd'))
    }
    foreach ($dir in @(Get-CommonDshDirs)) { $candidates.Add((Join-Path $dir 'resources\runtime\cli\bin\dsh.cmd')) }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $cli = [IO.Path]::GetFullPath($candidate)
            $exe = Resolve-DshExe -Cli $cli -Hint $DshExeHint
            return [pscustomobject]@{ Cli = $cli; Exe = $exe; Source = $candidate }
        }
    }
    return [pscustomobject]@{ Cli = $null; Exe = $null; Source = $null }
}

function Stop-DshForInstall {
    param(
        [string]$DshExe,
        [string]$LogPath
    )
    $procs = @(Get-DshProcesses -DshExe $DshExe)
    if ($procs.Count -eq 0) {
        Write-InstallerLog -LogPath $LogPath -Message 'DSH 当前未运行。'
        return $true
    }

    Write-InstallerLog -LogPath $LogPath -Message ("关闭 DSH：{0} 个进程。" -f $procs.Count)
    foreach ($proc in $procs) {
        try {
            if ($proc.MainWindowHandle -ne 0) { [void]$proc.CloseMainWindow() }
        } catch { }
    }

    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (@(Get-DshProcesses -DshExe $DshExe).Count -eq 0) { break }
    }

    $left = @(Get-DshProcesses -DshExe $DshExe)
    if ($left.Count -gt 0) {
        Write-InstallerLog -LogPath $LogPath -Message ("优雅退出超时，强制结束 {0} 个残留进程。" -f $left.Count)
        foreach ($proc in $left) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
        Start-Sleep -Seconds 2
    }

    $left = @(Get-DshProcesses -DshExe $DshExe)
    if ($left.Count -gt 0) {
        Write-InstallerLog -LogPath $LogPath -Message ("仍有 {0} 个 DSH 进程无法关闭。" -f $left.Count)
        return $false
    }
    Write-InstallerLog -LogPath $LogPath -Message 'DSH 已完全退出。'
    return $true
}

function Start-DshApp {
    param(
        [string]$DshExe,
        [string]$LogPath
    )
    if (-not $DshExe) {
        Write-InstallerLog -LogPath $LogPath -Message '未找到 DSH 可执行文件，请手动打开 DSH。'
        return $false
    }
    if (@(Get-DshProcesses -DshExe $DshExe).Count -gt 0) {
        Write-InstallerLog -LogPath $LogPath -Message 'DSH 已在运行，不重复启动。'
        return $true
    }

    Write-InstallerLog -LogPath $LogPath -Message '重新打开 DSH...'
    try {
        Start-Process -FilePath $DshExe -WorkingDirectory (Split-Path -Parent $DshExe) | Out-Null
    } catch {
        Write-InstallerLog -LogPath $LogPath -Message ('启动失败：' + $_.Exception.Message)
        return $false
    }

    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (@(Get-DshProcesses -DshExe $DshExe).Count -gt 0) { break }
    }
    if (@(Get-DshProcesses -DshExe $DshExe).Count -gt 0) {
        Write-InstallerLog -LogPath $LogPath -Message 'DSH 已重新启动。'
        return $true
    }
    Write-InstallerLog -LogPath $LogPath -Message 'DSH 启动超时，请手动打开。'
    return $false
}

function Backup-ProfileFiles {
    param(
        [string]$ProfileDir,
        [string]$Stamp,
        [string]$LogPath
    )
    $backup = Join-Path $ProfileDir ('_backup\dsh-startup-install-' + $Stamp)
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    $names = @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'cordis.patch.yml', 'desktop-plugins.lock.json')
    foreach ($name in $names) {
        $source = Join-Path $ProfileDir $name
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $backup $name) -Force
        }
    }
    Write-InstallerLog -LogPath $LogPath -Message ("已备份 profile 配置到：{0}" -f $backup)
    return $backup
}

function Find-DuplicateInsert {
    param([string]$PatchPath)
    if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) { return @() }

    $lines = @([IO.File]::ReadAllLines($PatchPath, [Text.Encoding]::UTF8))
    $ranges = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^\s*-\s*insert:\s*(#.*)?$') { continue }
        $indent = ([regex]::Match($lines[$i], '^(\s*)')).Groups[1].Value.Length
        $end = -1
        $limit = [Math]::Min($lines.Count - 1, $i + 30)
        for ($j = $i + 1; $j -le $limit; $j++) {
            $line = $lines[$j]
            if ($line.Trim().Length -eq 0) { continue }
            $jIndent = ([regex]::Match($line, '^(\s*)')).Groups[1].Value.Length
            if ($jIndent -le $indent -and $line -match '^\s*-\s') { break }
            if ($line -match 'dsh-startup-screen') { $end = $j; break }
        }
        if ($end -ge 0) { $ranges.Add([pscustomobject]@{ Start = $i; End = $end }) }
    }
    return $ranges.ToArray()
}

function Disable-DuplicateInsert {
    param(
        [string]$PatchPath,
        [object[]]$Ranges,
        [string]$LogPath
    )
    if (-not $Ranges -or $Ranges.Count -eq 0) { return 0 }
    $lines = @([IO.File]::ReadAllLines($PatchPath, [Text.Encoding]::UTF8))
    $count = 0
    foreach ($range in $Ranges) {
        for ($i = $range.Start; $i -le $range.End; $i++) {
            if ($lines[$i] -notmatch '^\s*#') {
                $lines[$i] = '# ' + $lines[$i]
                $count++
            }
        }
    }
    [IO.File]::WriteAllLines($PatchPath, $lines, $script:InstallerUtf8)
    Write-InstallerLog -LogPath $LogPath -Message ("已在 profile patch 中注释掉 {0} 行重复注册（原文件已备份）。" -f $count)
    return $count
}

function Get-InstalledVersion {
    param([string]$ProfileDir)
    $path = Join-Path $ProfileDir 'node_modules\dsh-startup-screen\package.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { return $null }
}

function Get-ProfileManifest {
    param([string]$ProfileDir)
    $path = Join-Path $ProfileDir 'package.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-LatestPackage {
    param(
        [string]$Root,
        [string]$Package
    )
    if ($Package) {
        if (-not (Test-Path -LiteralPath $Package -PathType Leaf)) { throw ("找不到安装包：{0}" -f $Package) }
        return [IO.Path]::GetFullPath($Package)
    }
    $found = @(Get-ChildItem -LiteralPath $Root -Filter 'dsh-startup-screen-*.tgz' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($found.Count -eq 0) { throw ("安装器目录里找不到 dsh-startup-screen-*.tgz：{0}" -f $Root) }
    return $found[0].FullName
}

function Get-PackageVersionFromFile {
    param([string]$Path)
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match '^dsh-startup-screen-(.+)$') { return $Matches[1] }
    return ''
}

function Test-Installation {
    param(
        [string]$Profile,
        [string]$ProfileDir,
        [string]$DshCli,
        [string]$ExpectedVersion,
        [string]$LogPath
    )
    $ok = $true

    $installed = Get-InstalledVersion -ProfileDir $ProfileDir
    if ($installed) {
        Write-InstallerLog -LogPath $LogPath -Message ("node_modules 版本：{0}" -f $installed)
        if ($ExpectedVersion -and $installed -ne $ExpectedVersion) {
            Write-InstallerLog -LogPath $LogPath -Message ("[FAIL] 版本不一致：期望 {0}，实际 {1}" -f $ExpectedVersion, $installed)
            $ok = $false
        }
    } else {
        Write-InstallerLog -LogPath $LogPath -Message '[FAIL] node_modules 里没有 dsh-startup-screen'
        $ok = $false
    }

    $manifest = Get-ProfileManifest -ProfileDir $ProfileDir
    $dep = $null
    if ($manifest -and $manifest.PSObject.Properties['dependencies']) {
        $dep = $manifest.dependencies.'dsh-startup-screen'
    }
    if ($dep) {
        Write-InstallerLog -LogPath $LogPath -Message ("profile 依赖：{0}" -f $dep)
    } else {
        Write-InstallerLog -LogPath $LogPath -Message '[FAIL] profile 依赖里没有 dsh-startup-screen'
        $ok = $false
    }

    $index = Join-Path $ProfileDir 'node_modules\dsh-startup-screen\lib\index.js'
    if (Test-Path -LiteralPath $index -PathType Leaf) {
        Write-InstallerLog -LogPath $LogPath -Message '插件入口文件存在。'
    } else {
        Write-InstallerLog -LogPath $LogPath -Message '[FAIL] 插件入口文件缺失'
        $ok = $false
    }

    $list = ''
    if ($DshCli) {
        try { $list = (& $DshCli plugin --profile $Profile list 2>&1 | Out-String) } catch { $list = '' }
    }
    $pattern = 'dsh-startup-screen@'
    if ($ExpectedVersion) { $pattern = 'dsh-startup-screen@' + [regex]::Escape($ExpectedVersion) }
    if ($list -match $pattern) {
        Write-InstallerLog -LogPath $LogPath -Message 'dsh plugin list 已包含插件。'
    } else {
        Write-InstallerLog -LogPath $LogPath -Message '[FAIL] dsh plugin list 里看不到插件'
        $ok = $false
    }

    return $ok
}