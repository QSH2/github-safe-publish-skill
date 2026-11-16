# verify-release-assets.ps1
# Verify GitHub Release assets exist (HTTP HEAD, following redirects) and optionally match SHA256.
# - Follows redirects, so a renamed repository (301) still verifies correctly.
# - Read-only; no token needed for public repos.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\verify-release-assets.ps1 `
#       -Repo "owner/repo" -AssetDir ".\release-assets" -CheckLatest -CheckHashes
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$true)][string]$AssetDir,
    [string[]]$Tags = @(),
    [switch]$CheckLatest,
    [string]$ExpectedLatest = "",
    [switch]$CheckHashes,
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'
$script:fail = 0
function Write-Ok([string]$m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Bad([string]$m)  { Write-Host "[FAIL] $m" -ForegroundColor Red; $script:fail++ }
function Write-Info([string]$m) { Write-Host "[INFO] $m" }

$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $curl) { throw "curl.exe not found (Windows 10+ includes it)" }
if ($Repo -notmatch '^[^/]+/[^/]+$') { throw "Repo must be owner/repo" }
$AssetDir = (Resolve-Path $AssetDir).Path

# HEAD with redirects followed; returns final code + effective URL.
# Final asset URL is release-assets.githubusercontent.com and returns 200.
function Get-Head([string]$url) {
    $fmt = "%{http_code}|%{url_effective}"
    $out = (& $curl -s -o NUL -w $fmt -I -L --max-time $TimeoutSec -H "User-Agent: Mozilla/5.0" $url 2>$null).Trim()
    $parts = $out -split '\|', 2
    if ($parts.Count -lt 2) { return [pscustomobject]@{ Code = ""; Effective = "" } }
    return [pscustomobject]@{ Code = $parts[0]; Effective = $parts[1] }
}

function Get-Asset([string]$url, [string]$dest) {
    & $curl -sL --max-time 120 -o $dest $url 2>$null
    return (Test-Path $dest) -and ((Get-Item $dest).Length -gt 0)
}

$tagDirs = @(Get-ChildItem $AssetDir -Directory | Sort-Object Name)
if ($Tags.Count -gt 0) { $tagDirs = @($tagDirs | Where-Object { $Tags -contains $_.Name }) }
if ($tagDirs.Count -eq 0) { Write-Bad "no tag directories found under $AssetDir"; exit 1 }

foreach ($dir in $tagDirs) {
    $tag = $dir.Name
    $files = @(Get-ChildItem $dir.FullName -File | Sort-Object Name)
    if ($files.Count -eq 0) { Write-Bad "$tag : empty directory"; continue }
    Write-Info "$tag : $($files.Count) file(s)"
    foreach ($f in $files) {
        $url = "https://github.com/$Repo/releases/download/$([uri]::EscapeDataString($tag))/$([uri]::EscapeDataString($f.Name))"
        $head = Get-Head $url
        # GitHub asset final status is 200; some setups return 302 before CDN.
        if ($head.Code -eq '200' -or $head.Code -eq '302') {
            Write-Ok ("$tag/$($f.Name) -> $($head.Code)")
        } else {
            Write-Bad ("$tag/$($f.Name) -> $($head.Code) (missing)")
        }
    }

    if ($CheckHashes) {
        $sumFile = Join-Path $dir.FullName "SHA256SUMS-$tag.txt"
        if (Test-Path $sumFile) {
            $expected = @{}
            foreach ($line in Get-Content $sumFile -Encoding UTF8) {
                if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
                    $expected[$Matches[2].Trim()] = $Matches[1].ToLower()
                }
            }
            foreach ($f in $files) {
                if ($f.Name -eq "SHA256SUMS-$tag.txt") { continue }
                if (-not $expected.ContainsKey($f.Name)) { continue }
                $tmp = Join-Path $env:TEMP ("ghasset-" + [guid]::NewGuid().ToString('N') + ".bin")
                $url = "https://github.com/$Repo/releases/download/$([uri]::EscapeDataString($tag))/$([uri]::EscapeDataString($f.Name))"
                if (Get-Asset $url $tmp) {
                    $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
                    if ($actual -eq $expected[$f.Name]) { Write-Ok ("$tag/$($f.Name) sha256 match") }
                    else { Write-Bad ("$tag/$($f.Name) sha256 mismatch: remote=$actual expected=$($expected[$f.Name])") }
                } else { Write-Bad ("$tag/$($f.Name) download failed") }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Info "$tag : no SHA256SUMS-$tag.txt, skip hash check"
        }
    }
}

if ($CheckLatest) {
    $u = "https://github.com/$Repo/releases/latest"
    $head = Get-Head $u
    $loc = $head.Effective
    if ($loc -match 'github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/releases/tag/(?<tag>[^/?#]+)') {
        $latest = $Matches.tag
        $effectiveRepo = "$($Matches.owner)/$($Matches.repo)"
        if ($effectiveRepo -ne $Repo) {
            Write-Info "repository was renamed: $Repo -> $effectiveRepo (301 followed)"
        }
        Write-Info "latest release: $latest"
        if ($ExpectedLatest -and $latest -ne $ExpectedLatest) {
            Write-Bad "latest is $latest, expected $ExpectedLatest"
        } else { Write-Ok "latest release is correct" }
    } else {
        Write-Bad "cannot resolve /releases/latest (effective URL: $loc)"
    }
}

if ($script:fail -gt 0) { Write-Host "`n$($script:fail) failure(s)" -ForegroundColor Red; exit 1 }
Write-Host "`nall release assets OK" -ForegroundColor Green
exit 0
