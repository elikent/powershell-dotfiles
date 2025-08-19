<#
.SYNOPSIS
    Executes an external command and throws a terminating error on failure.

.DESCRIPTION
    A reusable helper function that executes an external command, captures its
    standard error, and throws a terminating PowerShell error if the command's
    exit code is non-zero. This simplifies error handling in calling scripts.

.PARAMETER Command
    The command, executable, or script to run (e.g. 'git', 'py', 'gh')

.PARAMETER Arguments
    An array of arguments to pass to the command.
    
.PARAMETER ErrorMessage
    A descriptive error message to include in the exception if the command fails.

.EXAMPLE
    # Dot-source the reusable helper function for command execution.
    . (Join-Path $PSScriptRoot 'Invoke-CommandOrThrow.ps1')
    Invoke-CommandOrThrow -Command "git" -Arguments "status" -ErrorMessage "Failed to run 'git status'."

.NOTES
    This script is intended to be dot-sourced into other scripts.
#>

function Invoke-CommandOrThrow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [object[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    $stdErrFile = [System.IO.Path]::GetTempFileName()
    try {
        # Execute the command, redirecting the standard error stream (2) to a temporary file.
        & $Command $Arguments 2> $stdErrFile
        # if last exit code was not 0, error thrown
        if ($LASTEXITCODE -ne 0) {
            $stdErrOutput = Get-Content $stdErrFile | Out-String
            # Using 'throw' creates a terminating error, stopping the script immediately.
            throw "ERROR: $ErrorMessage`nDetails: $stdErrOutput"
        }
    }
    finally {
        Remove-Item $stdErrFile -ErrorAction SilentlyContinue
    }
}