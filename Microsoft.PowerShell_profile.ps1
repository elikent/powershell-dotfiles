<#
.SYNOPSIS
    A collection of personal PowerShell aliases and functions to improve productivity.

.DESCRIPTION
    This profile contains navigation shortcuts and automation scripts.
    The primary function is New-PyProject, which scaffolds a complete
    Python project environment.

.TODO
    Next steps for this PowerShell environment:

    - [x] pyenv-win Setup (Done)
    - [ ] Version Control Profile (Done)
    
    The environment is fully configured and ready for use.
#>


# --- PowerShell Profile ---
# This script runs at the start of every PowerShell session.

Write-Host "Welcome back! Your custom profile is loaded." -ForegroundColor Cyan

# --- pyenv-win Configuration ---
# Ensures pyenv-win is correctly configured for the shell session.
# PYENV_ROOT and PYENV_HOME point to the installation directory.
# The 'bin' and 'shims' directories are added to the front of the PATH
# to ensure pyenv's shims are used over any system-installed Python.
$PyenvWinPath = Join-Path $env:USERPROFILE ".pyenv\pyenv-win"
if (Test-Path -Path $PyenvWinPath) {
    $env:PYENV_ROOT = $PyenvWinPath
    $env:PYENV_HOME = $env:PYENV_ROOT
    $PyenvBinPath   = Join-Path $env:PYENV_ROOT "bin"
    $PyenvShimsPath = Join-Path $env:PYENV_ROOT "shims"
    $env:PATH = "$PyenvShimsPath;$PyenvBinPath;$($env:PATH)"
}

# --- Global Configuration Variables ---
# Define common paths in one place to be used by functions and scripts.
# These variables power the dynamic navigation and project creation functions.
#
# CONVENTION: To add a new project root directory that is automatically
# discovered by helper functions like 'go' (Set-Project) and 'New-PyProject',
# create a new global variable with a name that ends in 'ProjectsPath'.
# The part of the name before 'ProjectsPath' becomes the 'ProjectType'
# (e.g., 'Personal', 'Work').

$global:PersonalProjectsPath = "D:\my-projects\personal"
$global:WorkProjectsPath     = "D:\my-projects\work"

# --- Load Profile Components ---
# Dot-source component scripts to make their functions and aliases available.
# This keeps the main profile clean and focused on configuration.
. "$PSScriptRoot\profile_components\navigation.ps1"
. "$PSScriptRoot\functions\New-PyProject.ps1"
