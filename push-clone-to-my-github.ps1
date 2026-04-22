<#
.SYNOPSIS
  Point this repo at your new GitHub remote and push all branches and tags (full history stays local).

.PARAMETER NewRepoUrl
  Your repository URL. If omitted, uses environment variable NEW_GITHUB_REPO_URL.

.PARAMETER RepoRoot
  Path to the cloned repo (default: current directory).

.PARAMETER KeepUpstream
  Rename current "origin" to "upstream" and add your URL as "origin".
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string] $NewRepoUrl,

    [string] $RepoRoot = ".",

    [switch] $KeepUpstream
)

$ErrorActionPreference = "Stop"
if (-not $NewRepoUrl) { $NewRepoUrl = $env:NEW_GITHUB_REPO_URL }
if (-not $NewRepoUrl) {
    throw "Pass -NewRepoUrl 'https://github.com/You/your-repo.git' or set environment variable NEW_GITHUB_REPO_URL."
}

$resolved = Resolve-Path -LiteralPath $RepoRoot
Push-Location $resolved

try {
    if (-not (Test-Path -LiteralPath ".git")) {
        throw "Not a git repository: $resolved"
    }

    $shallow = git rev-parse --is-shallow-repository 2>$null
    if ($shallow -eq "true") {
        throw "This clone is shallow (incomplete history). Run: git fetch --unshallow   (then re-run this script), or re-clone without --depth."
    }

    $oldOrigin = git remote get-url origin 2>$null
    if (-not $oldOrigin) {
        throw "No remote named 'origin'. Add it or use a clone that had origin set."
    }

    if ($PSCmdlet.ShouldProcess($NewRepoUrl, "Configure remotes and push all refs")) {
        if ($KeepUpstream) {
            git remote rename origin upstream
            git remote add origin $NewRepoUrl
        }
        else {
            git remote set-url origin $NewRepoUrl
        }

        git push -u origin --all
        if ($LASTEXITCODE -ne 0) {
            if (-not $KeepUpstream) { git remote set-url origin $oldOrigin }
            else {
                git remote remove origin 2>$null | Out-Null
                git remote rename upstream origin 2>$null | Out-Null
            }
            throw "git push --all failed (exit $LASTEXITCODE). Local remotes were restored to the previous setup."
        }
        git push origin --tags
        if ($LASTEXITCODE -ne 0) {
            throw "git push --tags failed (exit $LASTEXITCODE). Branches may already be on the new remote; fix auth/network then run: git push origin --tags"
        }
    }
}
finally {
    Pop-Location
}
