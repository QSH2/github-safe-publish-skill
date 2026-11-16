# check-ssh-github.ps1
# Read-only check: SSH auth to GitHub, remote refs, local-vs-remote tree equality, tags.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\check-ssh-github.ps1 -RepoPath "." -Repo "owner/repo"
[CmdletBinding()]
param(
    [string]$RepoPath = ".",
    [string]$Repo = "",
    [string]$Branch = "main",
    [string]$Remote = "origin",
    [string]$SshExe = ""
)

$ErrorActionPreference = 'Continue'
$script:fail = 0

function Write-Ok([string]$m)   { Write-Host "[OK]   $m" -ForegroundColor Green }
function Write-Bad([string]$m)  { Write-Host "[FAIL] $m" -ForegroundColor Red; $script:fail++ }
function Write-Info([string]$m) { Write-Host "[INFO] $m" }

# Run a native command and capture stdout+stderr (PowerShell 5.1 turns native stderr into
# ErrorRecords; with ErrorActionPreference=Stop that aborts the script, so use Capture).
function Invoke-Capture {
    param([string]$Exe, [string[]]$Arguments)
    $output = (& $Exe @Arguments 2>&1 | Out-String).Trim()
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { Write-Bad "git not found in PATH"; exit 1 }
$git = $gitCmd.Source

$RepoPath = (Resolve-Path $RepoPath).Path
Push-Location $RepoPath
try {
    # ---- locate ssh ----
    if (-not $SshExe) {
        $cmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
        if ($cmd) { $SshExe = $cmd.Source }
        elseif (Test-Path "$env:LOCALAPPDATA\Programs\OpenSSH\ssh.exe") {
            $SshExe = "$env:LOCALAPPDATA\Programs\OpenSSH\ssh.exe"
        }
    }

    # ---- derive repo from remote if not provided ----
    if (-not $Repo) {
        $r = Invoke-Capture $git @('-C', $RepoPath, 'remote', 'get-url', $Remote)
        if ($r.Output -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)') {
            $Repo = "$($Matches.owner)/$($Matches.repo)"
        }
    }
    if (-not $Repo) { Write-Bad "cannot determine owner/repo; pass -Repo" }
    else { Write-Info "repository: $Repo" }

    # ---- SSH auth ----
    if ($SshExe -and (Test-Path $SshExe)) {
        $r = Invoke-Capture $SshExe @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new','-T','git@github.com')
        if ($r.Output -match 'successfully authenticated') {
            Write-Ok ("SSH: " + (($r.Output -split "`n") | Where-Object { $_ -match 'successfully authenticated' } | Select-Object -First 1))
        } else {
            Write-Bad "SSH auth failed: $($r.Output)"
        }
    } else {
        Write-Info "ssh.exe not found; skip SSH auth check"
    }

    # ---- refs ----
    $r = Invoke-Capture $git @('-C', $RepoPath, 'ls-remote', '--heads', '--tags', $Remote)
    if ($r.ExitCode -ne 0) { Write-Bad "git ls-remote failed: $($r.Output)" }
    else {
        $lines = @($r.Output -split "`n" | Where-Object { $_ -match "refs/(heads|tags)/" })
        $remoteHeads = @($lines | Where-Object { $_ -match "refs/heads/" } | ForEach-Object { ((($_ -split "`t")[1]) -replace 'refs/heads/','').Trim() })
        $remoteTags  = @($lines | Where-Object { $_ -match "refs/tags/" -and $_ -notmatch '\^\{\}' } | ForEach-Object { ((($_ -split "`t")[1]) -replace 'refs/tags/','').Trim() })
        Write-Info ("remote heads: " + ($remoteHeads -join ', '))
        Write-Info ("remote tags : " + ($remoteTags -join ', '))
        if ($remoteHeads -notcontains $Branch) { Write-Bad "remote branch '$Branch' missing" }
    }

    # ---- fetch + tree compare ----
    $null = Invoke-Capture $git @('-C', $RepoPath, 'fetch', $Remote, '--prune')
    $localTree  = (Invoke-Capture $git @('-C', $RepoPath, 'rev-parse', "$Branch^{tree}")).Output
    $remoteRef  = "$Remote/$Branch"
    $remoteTree = (Invoke-Capture $git @('-C', $RepoPath, 'rev-parse', "$remoteRef^{tree}")).Output
    Write-Info "local  tree: $localTree"
    Write-Info "remote tree: $remoteTree"
    if ($localTree -and $remoteTree -and $localTree -eq $remoteTree) { Write-Ok "tree identical" }
    else { Write-Bad "tree differs (repo may be incomplete or history diverged)" }

    # ---- file counts ----
    $localCount  = (Invoke-Capture $git @('-C', $RepoPath, 'ls-files')).Output -split "`n" | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
    $remoteList  = (Invoke-Capture $git @('-C', $RepoPath, 'ls-tree', '-r', '--name-only', $remoteRef)).Output -split "`n" | Where-Object { $_ }
    $remoteCount = @($remoteList).Count
    Write-Info "files: local=$localCount remote=$remoteCount"
    if ($localCount -ne $remoteCount) { Write-Bad "file count mismatch" } else { Write-Ok "file count matches" }

    # ---- tags ----
    if ($Repo) {
        $localTags = @((Invoke-Capture $git @('-C', $RepoPath, 'tag', '--list')).Output -split "`n" | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        Write-Info ("local tags: " + ($localTags -join ', '))
        if ($remoteTags -and $localTags.Count -gt 0) {
            $missing = @($localTags | Where-Object { $remoteTags -notcontains $_ })
            if ($missing.Count -gt 0) { Write-Bad ("tags missing on remote: " + ($missing -join ', ')) }
            else { Write-Ok "all local tags are on remote" }
        }
    }
}
finally {
    Pop-Location
}

if ($script:fail -gt 0) { Write-Host "`n$($script:fail) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "`nall checks passed" -ForegroundColor Green
exit 0
