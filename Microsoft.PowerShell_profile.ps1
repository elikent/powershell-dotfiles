<#
.SYNOPSIS
    A collection of personal PowerShell aliases and functions to improve productivity.

.DESCRIPTION
    This profile contains navigation shortcuts and automation scripts.
    The primary function is New-PyProject, which scaffolds a complete
    Python project environment.

.TODO
    Next steps for this PowerShell environment:

    This profile is version-controlled and configured for use.
    Future tasks can be tracked via GitHub Issues.
#>


# --- PowerShell Profile ---
# This script runs at the start of every PowerShell session.

Write-Host "Welcome back! Your custom profile is loaded." -ForegroundColor Cyan

# --- pyenv-win Configuration ---
# Ensures pyenv-win is correctly configured for the shell session.
# PYENV_ROOT and PYENV_HOME point to the installation directory.
# The 'bin' and 'shims' directories are added to the front of the PATH
# to ensure pyenv's shims are used over any system-installed Python.
$PyenvWinPath = Join-Path $HOME ".pyenv\pyenv-win"
if (Test-Path -Path $PyenvWinPath) {
    $env:PYENV_ROOT = $PyenvWinPath
    $env:PYENV_HOME = $env:PYENV_ROOT
    $PyenvBinPath   = Join-Path $env:PYENV_ROOT "bin"
    $PyenvShimsPath = Join-Path $env:PYENV_ROOT "shims"
    if ($env:PATH -notlike "*$PyenvShimsPath*") {
        $env:PATH = "$PyenvShimsPath;$PyenvBinPath;$($env:PATH)"
    }
}

# --- Global Configuration Variables ---
# Define common paths in one place to be used by functions and scripts.
# These variables power the dynamic navigation and project creation functions.
 
# A hashtable defining the root directories for different project types.
# Helper functions like 'go' (Set-Project) and 'New-PyProject' can
# iterate over this single object instead of discovering variables by name.
$global:ProjectTypeRoots = @{
    Personal = "D:\my-projects\personal"
    Work     = "D:\my-projects\work"
}

# --- Load Profile Components ---
# Dot-source component scripts to make their functions and aliases available.
# This keeps the main profile clean and focused on configuration.
. "$PSScriptRoot\profile_components\navigation.ps1"
. "$PSScriptRoot\functions\New-PyProject.ps1"
