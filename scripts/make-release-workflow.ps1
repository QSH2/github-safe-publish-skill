# make-release-workflow.ps1
# Generate a temporary GitHub Actions workflow that creates/updates Releases
# from per-tag asset directories using the repo-scoped GITHUB_TOKEN.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\make-release-workflow.ps1 `
#       -ManifestPath .\release-manifest.json -OutFile .\.github\workflows\create-releases.yml -DebugLog
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [string]$Branch = "",
    [int]$SleepSeconds = 20,
    [switch]$DebugLog,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$ManifestPath = (Resolve-Path $ManifestPath).Path
$raw = Get-Content $ManifestPath -Raw -Encoding UTF8
$manifest = $raw | ConvertFrom-Json

if (-not $manifest.releases -or @($manifest.releases).Count -eq 0) { throw "manifest.releases is empty" }
if (-not $Branch) {
    if ($manifest.branch) { $Branch = $manifest.branch } else { $Branch = "ci/release-assets" }
}
if ($PSBoundParameters.ContainsKey('SleepSeconds') -eq $false -and $manifest.sleepSeconds) {
    $SleepSeconds = [int]$manifest.sleepSeconds
}

$releases = @($manifest.releases)
for ($i = 0; $i -lt $releases.Count; $i++) {
    $r = $releases[$i]
    if (-not $r.tag)   { throw "releases[$i].tag missing" }
    if (-not $r.title) { throw "releases[$i].title missing" }
    if (-not $r.notes) { throw "releases[$i].notes missing" }
    if (-not $r.assets) { $releases[$i] | Add-Member -NotePropertyName assets -NotePropertyValue ("release-assets/" + $r.tag + "/*") -Force }
    if ($i -lt $releases.Count - 1 -and $r.latest -eq $true) {
        throw "only the last release may have latest=true (found at $($r.tag))"
    }
}

function ConvertTo-YamlDoubleQuoted([string]$s) {
    if ($null -eq $s) { return '""' }
    return '"' + ($s.Replace('\','\\').Replace('"','\"')) + '"'
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("name: create-releases")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("on:")
[void]$sb.AppendLine("  push:")
[void]$sb.AppendLine("    branches:")
[void]$sb.AppendLine("      - $Branch")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("permissions:")
[void]$sb.AppendLine("  contents: write")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("jobs:")
[void]$sb.AppendLine("  create:")
[void]$sb.AppendLine("    runs-on: ubuntu-latest")
[void]$sb.AppendLine("    steps:")
[void]$sb.AppendLine("      - uses: actions/checkout@v4")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("      - name: Create or update releases")
[void]$sb.AppendLine("        env:")
[void]$sb.AppendLine("          GH_TOKEN: `${{ secrets.GITHUB_TOKEN }}")
[void]$sb.AppendLine("        run: |")
if ($DebugLog) {
    [void]$sb.AppendLine("          exec > >(tee ci-debug.txt) 2>&1")
}
[void]$sb.AppendLine("          set -e")
[void]$sb.AppendLine("          gh --version")

for ($i = 0; $i -lt $releases.Count; $i++) {
    $r = $releases[$i]
    $tag = $r.tag
    $title = ConvertTo-YamlDoubleQuoted $r.title
    $notes = $r.notes
    $assets = $r.assets
    $latestFlag = ""
    if ($i -lt $releases.Count - 1 -or $r.latest -eq $false) { $latestFlag = " --latest=false" }

    [void]$sb.AppendLine("          if gh release view `"$tag`" >/dev/null 2>&1; then")
    [void]$sb.AppendLine("            gh release upload `"$tag`" $assets --clobber")
    [void]$sb.AppendLine("          else")
    [void]$sb.AppendLine("            gh release create `"$tag`" --verify-tag --title $title --notes-file `"$notes`"$latestFlag $assets")
    [void]$sb.AppendLine("          fi")
    if ($i -lt $releases.Count - 1) {
        [void]$sb.AppendLine("          sleep $SleepSeconds")
    }
}

if ($DebugLog) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("      - name: Commit debug output")
    [void]$sb.AppendLine("        if: always()")
    [void]$sb.AppendLine("        run: |")
    [void]$sb.AppendLine("          git config user.name `"ci-debug`"")
    [void]$sb.AppendLine("          git config user.email `"ci-debug@users.noreply.github.com`"")
    [void]$sb.AppendLine("          git add ci-debug.txt || true")
    [void]$sb.AppendLine("          git commit -m `"ci debug output [skip ci]`" || true")
    [void]$sb.AppendLine("          git push origin HEAD:refs/heads/$Branch || true")
}

if ([System.IO.Path]::IsPathRooted($OutFile)) { $outFull = $OutFile } else { $outFull = Join-Path (Get-Location) $OutFile }
$outDir = Split-Path -Parent $outFull
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if ((Test-Path $outFull) -and -not $Force) { throw "$outFull exists; pass -Force to overwrite" }
[System.IO.File]::WriteAllText($outFull, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "workflow written: $OutFile"
Write-Host ("releases: {0}, branch: {1}, sleep: {2}s, debugLog: {3}" -f $releases.Count, $Branch, $SleepSeconds, [bool]$DebugLog)
