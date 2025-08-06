<#
.SYNOPSIS
    Scaffolds a complete Python project environment.

.DESCRIPTION
    Creates a new project directory with Git, a standard .gitignore,
    a Python virtual environment pinned to a specific version via pyenv,
    and other optional setup steps.

.PARAMETER ProjectName
    The name of the project folder to be created.

.PARAMETER ProjectType
    The type of project, which determines the base directory.
    Must match a global '*ProjectsPath' variable name (e.g., 'Personal', 'Work').

.PARAMETER GitHubRemoteUrl
    Optional. The full git remote URL from GitHub to add as 'origin'.

.PARAMETER OpenInCode
    Optional. If present, opens the new project in Visual Studio Code upon completion.

.PARAMETER PythonVersion
    Optional. A specific Python version to use (e.g., "3.11.4").
    Requires pyenv. Defaults to the version set by 'pyenv global'.

.PARAMETER Requirements
    Optional. The path to a requirements.txt file to install into the venv.

.EXAMPLE
    New-PyProject -ProjectName "MyWebApp" -ProjectType "Personal" -PythonVersion "3.11.4" -OpenInCode

.EXAMPLE
    New-PyProject -ProjectName "DataAnalysis" -ProjectType "Work" -GitHubRemoteUrl "git@github.com:user/repo.git"

#>

# Script-scoped cache for available project types to avoid redundant lookups.
$Script:AvailableProjectTypes = (Get-Variable -Scope Global -Name "*ProjectsPath" -ErrorAction SilentlyContinue).Name -replace 'ProjectsPath', ''

# Internal helper function to execute external commands and throw a terminating error on failure.
# This simplifies error handling in the main function body.
function private:Invoke-CommandOrThrow {
    # parameters = mandatory command (eg git, pyenv), optional arguments, and mandatory error message
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [object[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    # calls command + args
    & $Command $Arguments
    # if last exit code was not 0, error thrown
    if ($LASTEXITCODE -ne 0) {
        # Using 'throw' creates a terminating error, stopping the script immediately.
        throw "ERROR: $ErrorMessage (Command: '$Command $Arguments' failed)"
    }
}

function New-PyProject {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true, HelpMessage = "The name of the project folder.")]
        [string]$ProjectName,

        [Parameter(Mandatory = $true, HelpMessage = "The project type (e.g., 'Personal', 'Work'). Must match a configured *ProjectsPath global variable.")]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $Script:AvailableProjectTypes | Where-Object { $_ -like "*$wordToComplete*" }
        })]
        [ValidateScript({
            if ($_ -in $Script:AvailableProjectTypes) {
                $true
            } else {
                throw "Invalid ProjectType '$_'. Available types are: $($Script:AvailableProjectTypes -join ', ')"
            }
        })]
        [string]$ProjectType,

        [Parameter(Mandatory = $false, HelpMessage = "The full git remote URL from GitHub.")]
        [string]$GitHubRemoteUrl,

        [Parameter(Mandatory = $false, HelpMessage = "If present, opens the new project in Visual Studio Code.")]
        [switch]$OpenInCode,

        [Parameter(Mandatory = $false, HelpMessage = "Specify a Python version to use (requires pyenv). Defaults to your global pyenv version.")]
        [string]$PythonVersion,

        [Parameter(Mandatory = $false, HelpMessage = "Path to a requirements.txt file to install after venv creation.")]
        [string]$Requirements
    )

    # --- Configuration & Path Setup ---
    # Construct the ProjectBaseDirName from $ProjectType then get path value from global variable.
    $ProjectBaseDirVarName = $ProjectType + "ProjectsPath"
    $ProjectsBaseDir = Get-Variable -Name $ProjectBaseDirVarName -Scope Global -ValueOnly -ErrorAction SilentlyContinue

    if (-not $ProjectsBaseDir -or -not (Test-Path -Path $ProjectsBaseDir -PathType Container)) {
        Write-Error "Project base directory for type '$ProjectType' is not defined or does not exist. Ensure `$global:$ProjectBaseDirVarName is set correctly in your profile."
        return
    }
    $NewProjectPath = Join-Path -Path $ProjectsBaseDir -ChildPath $ProjectName

    # --- Resolve Optional Paths ---
    # Resolve the requirements path BEFORE changing directory to avoid ambiguity with relative paths.
    $resolvedRequirementsPath = $null
    if ($PSBoundParameters.ContainsKey('Requirements')) {
        $resolvedRequirementsPath = Resolve-Path -LiteralPath $Requirements -ErrorAction SilentlyContinue
        if (-not $resolvedRequirementsPath) {
            Write-Warning "Requirements file not found at '$Requirements'. Will skip dependency installation."
            # Explicitly nullify to ensure the install step is skipped later
            $resolvedRequirementsPath = $null
        }
    }

    # --- Pre-flight Checks ---
    # Check to see if pyenv is installed
    $requiredCommands = @("git", "pyenv")
    foreach ($command in $requiredCommands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            Write-Error "The '$command' command was not found. Please ensure it is installed and in your PATH."
            return
        }
    }

    if (Test-Path $NewProjectPath) {
        Write-Error "Project '$ProjectName' already exists at '$NewProjectPath'."
        return
    }

    Write-Host "Setting up new Python project: $ProjectName" -ForegroundColor Green

    # Create the project directory and navigate into it
    New-Item -ItemType Directory -Path $NewProjectPath | Out-Null
    Set-Location $NewProjectPath

    # --- Git Setup ---
    Write-Host "-> Initializing Git repository and creating .gitignore..."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "init" -ErrorMessage "Failed to initialize Git repository."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "branch", "-M", "main" -ErrorMessage "Failed to rename default branch to 'main'."

    # Copy the standard Python .gitignore file from the templates folder in $PSScriptRoot (root folder for PROFILE)
    $GitignoreTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath "templates\.gitignore_python"
    if (Test-Path $GitignoreTemplatePath) {
        Copy-Item -Path $GitignoreTemplatePath -Destination .\.gitignore
    }
    else {
        Write-Warning "Could not find .gitignore template at '$GitignoreTemplatePath'. Creating a minimal .gitignore file."
        # Create a basic .gitignore to at least ignore the venv folder
        ".venv/" | Out-File -FilePath .\.gitignore -Encoding utf8
    }

    # --- venv Setup ---
    # Determine which Python version to use and pin it.
    # get versionToUse from value of PythonVersion key in PSBoundParameters if exists. else get from pyenv global. 
    $VersionToUse = if ($PSBoundParameters.ContainsKey('PythonVersion')) { $PythonVersion } else { (pyenv global).Trim() }

    # if version has not been set, write error mesage and terminate project creation program
    if (-not $VersionToUse) {
        Write-Error "Could not determine Python version. No version specified and 'pyenv global' returned no output."
        return
    }

    # If program not terminated above write which version will be used 
    Write-Host "-> Pinning Python version to '$VersionToUse' using 'pyenv local'..."

    # Set pyenv local
    # pyenv local then 1) checks its own inventory to see if $VersionToUse is installed and
    # 2) creates the .python-version file which tells pyenv and future users which version to use for project.
    private:Invoke-CommandOrThrow -Command "pyenv" -Arguments "local", $VersionToUse -ErrorMessage "pyenv failed to set version '$VersionToUse'. Is it installed? (e.g., 'pyenv install $VersionToUse')"

    # All above worked. report.
    Write-Host "-> Creating Python virtual environment (.venv) with Python $VersionToUse..."
    # Create venv with specified python version
    private:Invoke-CommandOrThrow -Command "python" -Arguments "-m", "venv", ".venv" -ErrorMessage "Failed to create the Python virtual environment (.venv). Please check your Python installation."

    # --- Initial Dependency Installation ---
    if ($resolvedRequirementsPath) {
        Write-Host "-> Installing dependencies from '$($resolvedRequirementsPath.Path)'..."
        # Set $VenvPython as python.exe installed in venv and Directly use to run pip
        $VenvPython = Join-Path -Path $NewProjectPath -ChildPath ".venv\Scripts\python.exe"
        private:Invoke-CommandOrThrow -Command $VenvPython -Arguments "-m", "pip", "install", "-r", $resolvedRequirementsPath.Path -ErrorMessage "Failed to install dependencies from '$($resolvedRequirementsPath.Path)'. Please check the file contents and your network connection."
    }

    # --- README Generation ---
    Write-Host "-> Creating README.md..."
    # Creates a simple README with the project name as a level 1 heading.
    "# $ProjectName" | Out-File -FilePath "README.md" -Encoding utf8

    # --- Initial Commit and Remote ---
    Write-Host "-> Staging files for initial commit..."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "add", "." -ErrorMessage "Failed to stage files with 'git add'."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "commit", "-m", "'Initial commit: project structure and venv setup'" -ErrorMessage "Failed to create initial commit. Is your git user.name and user.email configured?"

    if ($PSBoundParameters.ContainsKey('GitHubRemoteUrl')) {
        Write-Host "-> Adding GitHub remote: $GitHubRemoteUrl"
        private:Invoke-CommandOrThrow -Command "git" -Arguments "remote", "add", "origin", $GitHubRemoteUrl -ErrorMessage "Failed to add GitHub remote."
    }

    # --- Final Instructions ---
    Write-Host "`nProject '$ProjectName' created successfully!" -ForegroundColor Green
    Write-Host "Next steps:"
    Write-Host "1. Activate your venv: " -NoNewline; Write-Host ".\.venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    if ($PSBoundParameters.ContainsKey('GitHubRemoteUrl')) {
        Write-Host "2. Push to GitHub: " -NoNewline; Write-Host "git push -u origin main" -ForegroundColor Yellow
    }

    # --- Open in VS Code if requested ---
    if ($OpenInCode) {
        Write-Host "`nOpening project in Visual Studio Code..." -ForegroundColor Cyan
        code .
    }

}
