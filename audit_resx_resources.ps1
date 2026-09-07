# LanzhuTool RESX audit script
# Usage:
#   .\audit_resx_resources.ps1
#   .\audit_resx_resources.ps1 -RootPath .\mp4box

param(
    [string]$RootPath = ".\mp4box"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path $RootPath
Write-Host "Scanning: $root" -ForegroundColor Cyan

$resxFiles = Get-ChildItem -Path $root -Filter *.resx -File -Recurse
if (-not $resxFiles) {
    Write-Host "No .resx files found." -ForegroundColor Yellow
    return
}

$allBinary = New-Object System.Collections.Generic.List[object]

foreach ($f in $resxFiles) {
    try {
        [xml]$xml = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        $nodes = @($xml.SelectNodes("/root/data"))

        foreach ($n in $nodes) {
            if ($null -eq $n) { continue }

            $mime = ""
            if ($n.Attributes["mimetype"]) {
                $mime = [string]$n.Attributes["mimetype"].Value
            }

            $type = ""
            if ($n.Attributes["type"]) {
                $type = [string]$n.Attributes["type"].Value
            }

            if ($mime -match "base64" -or $type -match "System.Drawing.(Icon|Bitmap)") {
                $value = ""
                if ($n.value) {
                    $value = [string]$n.value
                }

                $normalized = if ([string]::IsNullOrWhiteSpace($value)) { "" } else { ($value -replace "\s+", "") }
                $sha = ""

                if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
                    $stream = New-Object System.IO.MemoryStream(,$bytes)
                    try {
                        $sha = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
                    }
                    finally {
                        $stream.Dispose()
                    }
                }

                $allBinary.Add([pscustomobject]@{
                    File = $f.FullName
                    Name = if ($n.Attributes["name"]) { [string]$n.Attributes["name"].Value } else { "" }
                    MimeType = $mime
                    Type = $type
                    ValueLength = $normalized.Length
                    Sha256 = $sha
                }) | Out-Null
            }
        }
    }
    catch {
        Write-Host "Read failed: $($f.FullName) -> $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($allBinary.Count -eq 0) {
    Write-Host "No binary resource entries found." -ForegroundColor Green
    return
}

Write-Host "`n=== Binary resource count by file ===" -ForegroundColor Cyan
$allBinary |
    Group-Object File |
    Sort-Object Count -Descending |
    Select-Object @{N='File';E={$_.Name}}, Count |
    Format-Table -AutoSize

Write-Host "`n=== Duplicate binary resources (by SHA256) ===" -ForegroundColor Cyan
$dupGroups = $allBinary |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.Sha256) } |
    Group-Object Sha256 |
    Where-Object { $_.Count -gt 1 }

if (-not $dupGroups) {
    Write-Host "No duplicated binary resources found." -ForegroundColor Green
}
else {
    foreach ($g in $dupGroups) {
        Write-Host ("SHA256: {0}  Count: {1}" -f $g.Name, $g.Count) -ForegroundColor Yellow
        $g.Group |
            Select-Object File, Name, MimeType, Type, ValueLength |
            Format-Table -AutoSize
    }
}

Write-Host "`nSuggestion: move duplicate icons/images in localized .resx files to shared resources." -ForegroundColor DarkCyan
