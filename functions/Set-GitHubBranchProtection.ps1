
<#
.SYNOPSIS
    Sets standard branch protection rules for the 'main' branch of a GitHub repository.

.DESCRIPTION
    This function uses the 'gh' CLI to apply a standard set of branch protections
    to the 'main' branch of a specified repository. These protections are ideal for
    solo developers who want to enforce a pull-request-based workflow.

    The following rules are applied:
    - Admins are subject to the same rules (`enforce_admins=true`).
    - Pull requests are required, but no formal approvals are needed (`required_approving_review_count=0`).

.PARAMETER UserName
    The user or organization name that owns the GitHub repository (e.g., "elikent").

.PARAMETER RepoName
    The name of the GitHub repository (e.g., "my-cool-project").

.EXAMPLE
    Set-GitHubBranchProtection -UserName "elikent" -RepoName "my-cool-project"
#>

function Set-GitHubBranchProtection {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true, HelpMessage = "The GitHub user or organization name.")]
        [string]$UserName,

        [Parameter(Mandatory = $true, HelpMessage = "The name of the repository.")]
        [string]$RepoName
    )

    # Dot-source the reusable helper function for command execution.
    . (Join-Path $PSScriptRoot 'Invoke-CommandOrThrow.ps1')

    # --- Pre-flight Checks ---
    # Check to see if gh is installed
    $requiredCommand = "gh"
    if (-not (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) {
        Write-Error "The '$requiredCommand' command was not found. Please ensure it is installed and in your PATH."
        return
    }

    # --- Apply Branch Protections ---
    Write-Host "Applying branch protections to '$UserName/$RepoName' on branch 'main'..."

    # Define the API endpoint and the arguments for the gh command
    $apiEndpoint = "repos/$UserName/$RepoName/branches/main/protection"
    $ghArguments = @(
        "api",
        "--method", "PUT",
        $apiEndpoint,
        # Require at least one approving review on pull requests
        # Setting this to 0 allows a solo developer to merge their own PRs.
        "-f", "required_pull_request_reviews[required_approving_review_count]=0",
        # Enforce protections for administrators
        "-f", "enforce_admins=true",
        # These must be set to null to avoid errors if they aren't configured
        "-f", "required_status_checks=null",
        "-f", "restrictions=null"
    )

    Invoke-CommandOrThrow -Command "gh" -Arguments $ghArguments -ErrorMessage "Failed to apply branch protections. Ensure the repo exists and you have admin permissions."

    Write-Host "Successfully applied branch protections to '$UserName/$RepoName'." -ForegroundColor Green
}
