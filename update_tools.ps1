# LanzhuTool 工具自动更新脚本
# 使用方法: .\update_tools.ps1

param(
    [switch]$SkipBackup = $false,
    [switch]$Auto = $false,
    [string]$ToolsPath,
    [int]$RetryCount = 3,
    [int]$TimeoutSec = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ToolsPath)) {
    $ToolsPath = Join-Path $PSScriptRoot "tools"
}

$gpacPath = Join-Path $ToolsPath "video\gpac"
$mkvPath = Join-Path $ToolsPath "video\mkvtoolnix"
$audioPath = Join-Path $ToolsPath "audio\encoders"

$backupPath = Join-Path $PSScriptRoot ("tools_backup_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$toolConfig = [ordered]@{
    MP4Box = [ordered]@{
        DisplayName = "MP4Box (GPAC)"
        Url = "https://github.com/gpac/gpac/releases/download/v2.5-DEV/gpac-2.5-dev-wtk-win64.zip"
        TempArchive = Join-Path $env:TEMP "mp4box.zip"
        TempDir = Join-Path $env:TEMP "mp4box"
        Sha256 = ""   # 留空表示跳过哈希校验
    }
    MKVToolNix = [ordered]@{
        DisplayName = "MKVToolNix"
        Url = "https://github.com/mbunkus/mkvtoolnix/releases/download/release-82.0/mkvtoolnix-64-bit-82.0.7z"
        TempArchive = Join-Path $env:TEMP "mkvtoolnix.7z"
        TempDir = Join-Path $env:TEMP "mkvtoolnix"
        Sha256 = ""   # 留空表示跳过哈希校验
    }
}

function Remove-TempArtifacts {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    foreach ($path in $Paths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Download-FileWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [Parameter(Mandatory = $true)][int]$Retry,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $attempt = 0
    do {
        $attempt++
        try {
            Write-Host "下载中($attempt/$Retry): $Url" -ForegroundColor Gray
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSeconds
            return
        }
        catch {
            if ($attempt -ge $Retry) {
                throw
            }
            Write-Host "下载失败，3秒后重试: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    } while ($attempt -lt $Retry)
}

function Test-ArchiveHash {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$ExpectedSha256
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        Write-Host "⚠ 未配置 SHA256，跳过哈希校验" -ForegroundColor Yellow
        return $true
    }

    $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    if ($actual.Equals($ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "✓ SHA256 校验通过" -ForegroundColor Green
        return $true
    }

    Write-Host "✗ SHA256 校验失败" -ForegroundColor Red
    Write-Host "  期望: $ExpectedSha256" -ForegroundColor Red
    Write-Host "  实际: $actual" -ForegroundColor Red
    return $false
}

Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     LanzhuTool 工具更新脚本           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "工具目录: $ToolsPath" -ForegroundColor DarkCyan

if (-not (Test-Path $ToolsPath)) {
    New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
}
foreach ($p in @($gpacPath, $mkvPath, $audioPath)) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

# 备份原有工具
if (-not $SkipBackup) {
    Write-Host "`n正在备份原有工具..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

    foreach ($fileName in @("MP4Box.exe", "mkvmerge.exe", "neroAacEnc.exe", "mkvextract.exe", "mkvinfo.exe", "mmg.exe")) {
        $sources = Get-ChildItem -Path $ToolsPath -Filter $fileName -Recurse -File -ErrorAction SilentlyContinue
        foreach ($src in $sources) {
            $destName = (Split-Path -Leaf (Split-Path -Parent $src.FullName)) + "__" + $src.Name
            Copy-Item -Path $src.FullName -Destination (Join-Path $backupPath $destName) -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "✓ 备份已保存到: $backupPath" -ForegroundColor Green
}

# 下载 MP4Box
Write-Host "`n【1/3】正在下载 MP4Box (GPAC)..." -ForegroundColor Cyan
try {
    $cfg = $toolConfig.MP4Box
    Remove-TempArtifacts -Paths @($cfg.TempArchive, $cfg.TempDir)

    Download-FileWithRetry -Url $cfg.Url -OutFile $cfg.TempArchive -Retry $RetryCount -TimeoutSeconds $TimeoutSec
    if (-not (Test-ArchiveHash -FilePath $cfg.TempArchive -ExpectedSha256 $cfg.Sha256)) {
        throw "MP4Box 压缩包哈希不匹配，已停止更新。"
    }

    Expand-Archive -Path $cfg.TempArchive -DestinationPath $cfg.TempDir -Force
    $mp4boxExe = Get-ChildItem -Path $cfg.TempDir -Filter "MP4Box.exe" -Recurse -File | Select-Object -First 1

    if (-not $mp4boxExe) {
        throw "压缩包中未找到 MP4Box.exe"
    }

    Copy-Item -Path $mp4boxExe.FullName -Destination (Join-Path $gpacPath "MP4Box.exe") -Force
    Write-Host "✓ MP4Box 已更新" -ForegroundColor Green
    & (Join-Path $gpacPath "MP4Box.exe") -version 2>&1 | Select-Object -First 1
}
catch {
    Write-Host "✗ MP4Box 更新失败: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    $cfg = $toolConfig.MP4Box
    Remove-TempArtifacts -Paths @($cfg.TempArchive, $cfg.TempDir)
}

# 下载 MKVToolNix
Write-Host "`n【2/3】正在下载 MKVToolNix..." -ForegroundColor Cyan
try {
    $cfg = $toolConfig.MKVToolNix
    Remove-TempArtifacts -Paths @($cfg.TempArchive, $cfg.TempDir)

    Download-FileWithRetry -Url $cfg.Url -OutFile $cfg.TempArchive -Retry $RetryCount -TimeoutSeconds $TimeoutSec
    if (-not (Test-ArchiveHash -FilePath $cfg.TempArchive -ExpectedSha256 $cfg.Sha256)) {
        throw "MKVToolNix 压缩包哈希不匹配，已停止更新。"
    }

    $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
    if (-not $sevenZip) {
        $sevenZip = Get-Command 7za -ErrorAction SilentlyContinue
    }

    if (-not $sevenZip) {
        throw "未找到 7z/7za，可安装 7-Zip 后重试。"
    }

    & $sevenZip.Source x $cfg.TempArchive "-o$($cfg.TempDir)" -y | Out-Null

    $requiredTools = @("mkvmerge.exe", "mkvextract.exe", "mkvinfo.exe", "mmg.exe")
    $copied = 0
    foreach ($tool in $requiredTools) {
        $found = Get-ChildItem -Path $cfg.TempDir -Filter $tool -Recurse -File | Select-Object -First 1
        if ($found) {
            Copy-Item -Path $found.FullName -Destination (Join-Path $mkvPath $tool) -Force
            $copied++
        }
    }

    if ($copied -eq 0) {
        throw "未在压缩包中找到任何 MKVToolNix 核心工具。"
    }

    Write-Host "✓ MKVToolNix 已更新（$copied/$($requiredTools.Count)）" -ForegroundColor Green
    & (Join-Path $mkvPath "mkvmerge.exe") --version 2>&1 | Select-Object -First 1
}
catch {
    Write-Host "✗ MKVToolNix 更新失败: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    $cfg = $toolConfig.MKVToolNix
    Remove-TempArtifacts -Paths @($cfg.TempArchive, $cfg.TempDir)
}

# 下载 NeroAAC
Write-Host "`n【3/3】NeroAAC (可选)" -ForegroundColor Cyan
try {
    $url = "https://www.nero.com/enu/Nero-AAC-Codec/"
    Write-Host "NeroAAC 需要手动下载自: $url" -ForegroundColor Yellow
}
catch {
    Write-Host "✗ 无法获取 NeroAAC 信息" -ForegroundColor Red
}

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           更新完成!                   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
if (-not $SkipBackup) {
    Write-Host "备份位置: $backupPath" -ForegroundColor Green
}
Write-Host "更新位置: $ToolsPath" -ForegroundColor Green
