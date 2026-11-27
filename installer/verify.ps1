[CmdletBinding()]
param(
    [string]$Profile = 'desktop',
    [string]$DshCli = '',
    [string]$DshExe = '',
    [int]$Port = 0,
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
. (Join-Path $Root 'common.ps1')

Enable-Utf8Console


if (-not $LogPath) {
    $logDir = Get-InstallerLogDir
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $LogPath = Join-Path $logDir ("verify-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$script:Failed = 0
$script:Warned = 0

function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        $line = "[PASS] {0}：{1}" -f $Name, $Detail
        Write-Host $line
    } else {
        $line = "[FAIL] {0}：{1}" -f $Name, $Detail
        Write-Host $line
        $script:Failed++
    }
    try { [IO.File]::AppendAllText($LogPath, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

function Add-Warn {
    param([string]$Name, [string]$Detail)
    $line = "[WARN] {0}：{1}" -f $Name, $Detail
    Write-Host $line
    $script:Warned++
    try { [IO.File]::AppendAllText($LogPath, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

Write-Host '=============================================='
Write-Host 'dsh-startup-screen 安装验收'
Write-Host '=============================================='

$dsh = Resolve-DshCli -Hint $DshCli -DshExeHint $DshExe
if (-not $dsh.Cli) {
    Add-Check 'dsh CLI' $false '找不到 dsh。先打开一次 DSH 桌面端，或用 -DshCli 指定路径。'
    exit 1
}
Add-Check 'dsh CLI' $true $dsh.Cli

$profileDir = Get-DshProfileDir -Profile $Profile
$profileOk = Test-Path -LiteralPath $profileDir -PathType Container
Add-Check 'profile 目录' $profileOk $profileDir
if (-not $profileOk) { exit 1 }

$manifest = Get-ProfileManifest -ProfileDir $profileDir
$dep = $null
if ($manifest -and $manifest.PSObject.Properties['dependencies']) {
    $dep = $manifest.dependencies.'dsh-startup-screen'
}
Add-Check 'profile 依赖' ([bool]$dep) ([string]$dep)

$installed = Get-InstalledVersion -ProfileDir $profileDir
Add-Check 'node_modules 版本' ([bool]$installed) ([string]$installed)

$index = Join-Path $profileDir 'node_modules\dsh-startup-screen\lib\index.js'
Add-Check '插件入口' (Test-Path -LiteralPath $index -PathType Leaf) $index

$list = ''
try { $list = (& $dsh.Cli plugin --profile $Profile list 2>&1 | Out-String) } catch { $list = '' }
Add-Check 'dsh plugin list' ($list -match 'dsh-startup-screen@') ($list.Trim())

$cordisPath = Join-Path $profileDir 'cordis.yml'
$cordisOk = $false
if (Test-Path -LiteralPath $cordisPath -PathType Leaf) {
    $cordisText = Get-Content -LiteralPath $cordisPath -Raw -Encoding UTF8
    $cordisOk = $cordisText -match 'dsh-startup-screen'
}
$running = @(Get-DshProcesses -DshExe $dsh.Exe).Count -gt 0
if ($cordisOk) {
    Add-Check 'cordis.yml 条目' $true '已包含 dsh-startup-screen'
} elseif ($running) {
    Add-Check 'cordis.yml 条目' $false 'DSH 正在运行但配置树里没有插件，建议重启 DSH 后再验收'
} else {
    Add-Warn 'cordis.yml 条目' 'DSH 未运行，配置树可能还没生成；启动 DSH 后再跑一次验收'
}

$patchPath = Join-Path $profileDir 'cordis.patch.yml'
$duplicates = @(Find-DuplicateInsert -PatchPath $patchPath)
Add-Check '重复注册' ($duplicates.Count -eq 0) ("发现 {0} 段" -f $duplicates.Count)

if ($Port -gt 0) {
    $uri = "http://127.0.0.1:$Port/dsh-startup/splash.js"
    try {
        $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5
        Add-Check '路由' ($resp.StatusCode -eq 200) ("HTTP " + [int]$resp.StatusCode + "（" + $uri + "）")
    } catch {
        $status = 0
        if ($_.Exception.Response) {
            try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = 0 }
        }
        if ($status -eq 401) {
            Add-Check '路由' $true "HTTP 401（信任栅栏，正常；$uri）"
        } elseif ($status -eq 404) {
            Add-Check '路由' $false "HTTP 404（插件路由未注册；$uri）"
        } else {
            Add-Check '路由' $false ("请求失败：" + $_.Exception.Message)
        }
    }
} else {
    Add-Warn '路由' '未指定 -Port，跳过 HTTP 路由检查'
}

Write-Host ''
if ($script:Failed -eq 0) {
    Write-Host ("验收通过（警告 {0} 条）。日志：{1}" -f $script:Warned, $LogPath)
    exit 0
}
Write-Host ("验收未通过：{0} 项失败，{1} 条警告。日志：{2}" -f $script:Failed, $script:Warned, $LogPath)
exit 1