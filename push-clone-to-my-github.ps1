<#
.SYNOPSIS
  Point this repo at your new GitHub remote and push all branches and tags.

.DESCRIPTION
  Optionally rewrites EVERY commit so Author and Committer name/email match yours
  (uses git filter-branch). That changes all commit hashes and requires a force push.

  WARNING: Rewriting attribution on someone else's commits can misrepresent who wrote
  the code and may conflict with the project's license. Use only on forks you own and
  when you accept that risk. GPG signatures on old commits will no longer verify.

.PARAMETER NewRepoUrl
  Your repository URL. If omitted, uses environment variable NEW_GITHUB_REPO_URL.

.PARAMETER RepoRoot
  Path to the cloned repo (default: current directory).

.PARAMETER KeepUpstream
  Rename current "origin" to "upstream" and add your URL as "origin".

.PARAMETER RewriteAllCommitAuthors
  Run git filter-branch so all commits use -AuthorName / -AuthorEmail (or git config
  user.name / user.email). Then pushes with --force-with-lease. Irreversible without a backup clone.

.PARAMETER AuthorName
  Used with -RewriteAllCommitAuthors. Default: git config user.name

.PARAMETER AuthorEmail
  Used with -RewriteAllCommitAuthors. Default: git config user.email

.EXAMPLE
  .\push-clone-to-my-github.ps1 -NewRepoUrl https://github.com/Me/repo.git

.EXAMPLE
  .\push-clone-to-my-github.ps1 -NewRepoUrl https://github.com/Me/repo.git -RewriteAllCommitAuthors

.EXAMPLE
  .\push-clone-to-my-github.ps1 -NewRepoUrl https://github.com/Me/repo.git -RewriteAllCommitAuthors -AuthorName "My Name" -AuthorEmail "me@users.noreply.github.com"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string] $NewRepoUrl,

    [string] $RepoRoot = ".",

    [switch] $KeepUpstream,

    [switch] $RewriteAllCommitAuthors,

    [string] $AuthorName,

    [string] $AuthorEmail
)

function Escape-ShSingleQuote([string] $Value) {
    if ($null -eq $Value) { return "" }
    $Value -replace "'", "'\''"
}

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

    if ($RewriteAllCommitAuthors) {
        if (-not $AuthorName) { $AuthorName = git config user.name }
        if (-not $AuthorEmail) { $AuthorEmail = git config user.email }
        if (-not $AuthorName -or -not $AuthorEmail) {
            throw "For -RewriteAllCommitAuthors, set git config user.name and user.email, or pass -AuthorName and -AuthorEmail."
        }
        Write-Warning "Rewriting ALL commits to Author/Committer: $AuthorName <$AuthorEmail>. Original attribution will be lost. Make a backup clone if you might need the old history."
    }

    if ($PSCmdlet.ShouldProcess($NewRepoUrl, "Configure remotes and push all refs")) {
        if ($RewriteAllCommitAuthors) {
            $n = Escape-ShSingleQuote $AuthorName
            $e = Escape-ShSingleQuote $AuthorEmail
            $envFilter = "GIT_AUTHOR_NAME='$n'; GIT_AUTHOR_EMAIL='$e'; GIT_COMMITTER_NAME='$n'; GIT_COMMITTER_EMAIL='$e'; export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL"
            git filter-branch -f --env-filter $envFilter --tag-name-filter cat -- --branches --tags
            if ($LASTEXITCODE -ne 0) {
                throw "git filter-branch failed (exit $LASTEXITCODE). Fix the error above; your repo was not pushed."
            }
            git for-each-ref --format="delete %(refname)" refs/original | git update-ref --stdin
            git reflog expire --expire=now --all 2>$null | Out-Null
            git gc --prune=now --quiet 2>$null | Out-Null
        }

        if ($KeepUpstream) {
            git remote rename origin upstream
            git remote add origin $NewRepoUrl
        }
        else {
            git remote set-url origin $NewRepoUrl
        }

        $pushBranchArgs = @("push", "-u", "origin", "--all")
        if ($RewriteAllCommitAuthors) { $pushBranchArgs = @("push", "--force-with-lease", "-u", "origin", "--all") }
        & git @pushBranchArgs
        if ($LASTEXITCODE -ne 0) {
            if (-not $KeepUpstream) { git remote set-url origin $oldOrigin }
            else {
                git remote remove origin 2>$null | Out-Null
                git remote rename upstream origin 2>$null | Out-Null
            }
            throw "git push --all failed (exit $LASTEXITCODE). Local remotes were restored to the previous setup."
        }
        $pushTagArgs = @("push", "origin", "--tags")
        if ($RewriteAllCommitAuthors) { $pushTagArgs = @("push", "--force", "origin", "--tags") }
        & git @pushTagArgs
        if ($LASTEXITCODE -ne 0) {
            throw "git push --tags failed (exit $LASTEXITCODE). Branches may already be on the new remote; fix auth/network then run: git push origin --tags"
        }
    }
}
finally {
    Pop-Location
}
