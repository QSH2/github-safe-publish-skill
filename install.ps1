# install.ps1
# Copy this skill into an agent's skills directory.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -TargetRoot "D:\agents\skills" -Force
[CmdletBinding()]
param(
    [string]$TargetRoot = "$env:USERPROFILE\.dsh\skills",
    [string]$Name = "github-safe-publish",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$source = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $source "SKILL.md"))) {
    throw "SKILL.md not found next to install.ps1; run this from the skill root."
}

$target = Join-Path $TargetRoot $Name
Write-Host "source: $source"
Write-Host "target: $target"

if ((Test-Path $target) -and -not $Force) {
    Write-Host "target already exists. Use -Force to overwrite." -ForegroundColor Yellow
    exit 1
}

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
Copy-Item $source $target -Recurse -Force

Write-Host "installed: $target" -ForegroundColor Green
Write-Host "new agent sessions should discover skill '$Name' from SKILL.md." -ForegroundColor Green
