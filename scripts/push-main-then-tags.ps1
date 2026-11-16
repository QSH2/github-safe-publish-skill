# push-main-then-tags.ps1
# Safe push helper: push main first, wait, then push tags; optional bundle backup.
# Does NOT force-push. For force scenarios see references/02 and 03.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\push-main-then-tags.ps1 -RepoPath "." -DryRun
#   powershell -ExecutionPolicy Bypass -File scripts\push-main-then-tags.ps1 -RepoPath "." -BackupBundle
[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [string]$Remote = "origin",
    [string]$Branch = "main",
    [int]$WaitSeconds = 60,
    [switch]$BackupBundle,
    [string]$BundleDir = "E:\backups",
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
function Write-Info([string]$m) { Write-Host "[INFO] $m" }
function Fail([string]$m) { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }

function Invoke-Capture {
    param([string]$Exe, [string[]]$Arguments)
    $output = (& $Exe @Arguments 2>&1 | Out-String).Trim()
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { Fail "git not found in PATH" }
$git = $gitCmd.Source
$RepoPath = (Resolve-Path $RepoPath).Path

Push-Location $RepoPath
try {
    $remoteUrl = (Invoke-Capture $git @('-C', $RepoPath, 'remote', 'get-url', $Remote)).Output
    if (-not $remoteUrl) { Fail "remote '$Remote' not found" }
    Write-Info "repo: $RepoPath"
    Write-Info "remote: $Remote -> $remoteUrl"
    Write-Info "branch: $Branch"

    $status = (Invoke-Capture $git @('-C', $RepoPath, 'status', '-sb')).Output
    Write-Info "status: $status"
    $log = (Invoke-Capture $git @('-C', $RepoPath, 'log', '--oneline', '--decorate', '-3')).Output
    Write-Info "log:`n$log"

    if ($BackupBundle) {
        if (-not (Test-Path $BundleDir)) { New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null }
        $bundle = Join-Path $BundleDir ("pre-push-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".bundle")
        Write-Info "creating bundle: $bundle"
        if (-not $DryRun) {
            $r = Invoke-Capture $git @('-C', $RepoPath, 'bundle', 'create', $bundle, '--all')
            if ($r.ExitCode -ne 0) { Fail "git bundle create failed: $($r.Output)" }
            $v = Invoke-Capture $git @('bundle', 'verify', $bundle)
            if ($v.ExitCode -ne 0) { Fail "git bundle verify failed: $($v.Output)" }
            Write-Info "bundle created and verified"
        } else {
            Write-Info "(dry-run) git bundle create `"$bundle`" --all"
        }
    }

    $cmds = @(
        "git push -u $Remote $Branch",
        "Start-Sleep -Seconds $WaitSeconds",
        "git push $Remote --tags",
        "git ls-remote --heads --tags $Remote"
    )
    if ($DryRun) {
        Write-Host "`n(dry-run) would run:"
        $cmds | ForEach-Object { Write-Host "  $_" }
        exit 0
    }

    Write-Info "push $Branch ..."
    $r = Invoke-Capture $git @('-C', $RepoPath, 'push', '-u', $Remote, $Branch)
    if ($r.ExitCode -ne 0) { Fail "push $Branch failed: $($r.Output)" }
    Write-Host $r.Output

    Write-Info "wait $WaitSeconds s ..."
    Start-Sleep -Seconds $WaitSeconds

    Write-Info "push tags ..."
    $r = Invoke-Capture $git @('-C', $RepoPath, 'push', $Remote, '--tags')
    if ($r.ExitCode -ne 0) { Fail "push tags failed: $($r.Output)" }
    Write-Host $r.Output

    Write-Info "remote refs:"
    $r = Invoke-Capture $git @('-C', $RepoPath, 'ls-remote', '--heads', '--tags', $Remote)
    Write-Host $r.Output

    Write-Host "`npush completed" -ForegroundColor Green
}
finally {
    Pop-Location
}
