# LanzhuTool tools auto-updater (国内镜像源)
# Usage:
#   .\update_tools.ps1
#   .\update_tools.ps1 -ToolsRoot "C:\Tools\lanzhutool\tools"
#   .\update_tools.ps1 -ConfigUrl "https://example.com/tools_version.json"

param(
    [string]$ToolsRoot = $PSScriptRoot,
    [string]$ConfigUrl = "https://maruko.appinn.me/config/tools_version.json",
    [switch]$UseMirror = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 国内 GitHub 代理列表
$GH_MIRRORS = @(
    "https://mirror.ghproxy.com/",
    "https://ghps.cc/",
    "https://gh.api.99988866.xyz/"
)

function Get-MirrorUrl([string]$url) {
    if (-not $UseMirror) { return $url }
    if ($url -match "^https?://github\.com" -or $url -match "^https?://raw\.githubusercontent\.com") {
        return "https://mirror.ghproxy.com/$url"
    }
    return $url
}

function Get-LocalToolsVersion([string]$toolsRoot) {
    $localConfig = Join-Path $toolsRoot "tools_version.json"
    if (Test-Path $localConfig) {
        return Get-Content $localConfig -Raw -Encoding UTF8
    }
    return $null
}

function Save-LocalToolsVersion([string]$toolsRoot, [string]$json) {
    $localConfig = Join-Path $toolsRoot "tools_version.json"
    Set-Content $localConfig -Value $json -Encoding UTF8
}

function Invoke-ToolsUpdate {
    Write-Host "=== LanzhuTool tools updater ===" -ForegroundColor Cyan
    Write-Host ("ToolsRoot: {0}" -f $ToolsRoot) -ForegroundColor DarkCyan
    Write-Host ("ConfigUrl: {0}" -f $ConfigUrl) -ForegroundColor DarkCyan
    Write-Host ("UseMirror: {0}" -f $UseMirror) -ForegroundColor DarkCyan

    # 下载远程配置
    try {
        $remoteJson = Invoke-WebRequest -Uri $ConfigUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $remoteConfig = $remoteJson.Content | ConvertFrom-Json
    }
    catch {
        Write-Error ("下载远程配置失败: {0}" -f $_.Exception.Message)
        return 1
    }

    # 读取本地配置
    $localContent = Get-LocalToolsVersion -toolsRoot $ToolsRoot
    $localConfig = $null
    if ($localContent) {
        try { $localConfig = $localContent | ConvertFrom-Json } catch {}
    }

    $updated = 0
    $failed = 0
    $skipped = 0

    foreach ($tool in $remoteConfig.tools) {
        $localTool = $null
        if ($localConfig -and $localConfig.tools) {
            $localTool = $localConfig.tools | Where-Object { $_.name -eq $tool.name } | Select-Object -First 1
        }

        $needUpdate = $true
        if ($localTool -and $localTool.version -eq $tool.version) {
            $localPath = Join-Path $ToolsRoot $tool.path
            if (Test-Path $localPath) {
                $needUpdate = $false
            }
        }

        if (-not $needUpdate) {
            Write-Host ("[SKIP] {0} ({1})" -f $tool.name, $tool.version) -ForegroundColor DarkGreen
            $skipped++
            continue
        }

        Write-Host ("[UPDATE] {0} ({1})" -f $tool.name, $tool.version) -ForegroundColor Cyan

        $downloadUrl = Get-MirrorUrl -url $tool.url
        $tempFile = [System.IO.Path]::GetTempFileName()
        $targetPath = Join-Path $ToolsRoot $tool.path
        $bakPath = $targetPath + ".bak"

        try {
            # 创建目标目录
            $targetDir = Split-Path $targetPath -Parent
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            # 下载文件
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
            $ProgressPreference = 'Continue'

            # 如果有校验和，验证
            if ($tool.checksum) {
                $algo = $tool.checksumAlgo
                if (-not $algo) { $algo = "SHA256" }
                $hash = Get-FileHash -Path $tempFile -Algorithm $algo | Select-Object -ExpandProperty Hash
                $expected = $tool.checksum
                if ($hash -ne $expected) {
                    throw ("校验和不匹配: {0} != {1}" -f $hash, $expected)
                }
            }

            # 备份旧文件
            if (Test-Path $targetPath) {
                if (Test-Path $bakPath) { Remove-Item $bakPath -Force }
                Move-Item $targetPath $bakPath -Force
            }

            # 如果是 zip，解压
            if ($downloadUrl -match "\.zip$" -or $tool.extract -eq "zip") {
                $extractDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                Expand-Archive -Path $tempFile -DestinationPath $extractDir -Force
                # 复制解压后的文件
                if ($tool.extractPath) {
                    $src = Join-Path $extractDir $tool.extractPath
                    if (Test-Path $src) {
                        Copy-Item $src $targetPath -Force
                    }
                    else {
                        throw ("解压后找不到指定路径: {0}" -f $tool.extractPath)
                    }
                }
                else {
                    # 查找解压目录中的对应文件名
                    $leaf = Split-Path $tool.path -Leaf
                    $found = Get-ChildItem $extractDir -Recurse -Filter $leaf | Select-Object -First 1
                    if ($found) {
                        Copy-Item $found.FullName $targetPath -Force
                    }
                    else {
                        throw ("解压后找不到文件: {0}" -f $leaf)
                    }
                }
                Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            else {
                Move-Item $tempFile $targetPath -Force
            }

            # 清理临时文件
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }

            $updated++
            Write-Host ("[OK] {0}" -f $tool.name) -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Host ("[FAIL] {0}: {1}" -f $tool.name, $_.Exception.Message) -ForegroundColor Red
            # 恢复备份
            if (Test-Path $bakPath) {
                if (Test-Path $targetPath) { Remove-Item $targetPath -Force }
                Move-Item $bakPath $targetPath -Force
            }
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }

    # 保存本地配置（只有全部成功才保存，失败则保留旧配置以便下次重试）
    if ($updated -gt 0 -and $failed -eq 0) {
        Save-LocalToolsVersion -toolsRoot $ToolsRoot -json ($remoteConfig | ConvertTo-Json -Depth 10)
    }

    Write-Host ("`n更新完成: {0} 成功, {1} 跳过, {2} 失败" -f $updated, $skipped, $failed) -ForegroundColor Cyan

    if ($failed -gt 0) {
        return 1
    }
    return 0
}

# 主入口
$exitCode = Invoke-ToolsUpdate
exit $exitCode
