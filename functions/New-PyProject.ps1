<#
.SYNOPSIS
    Scaffolds a complete Python project environment.

.DESCRIPTION
    Creates a new project directory with Git, a standard .gitignore,
    a Python virtual environment pinned to a specific version via pyenv,
    and other optional setup steps, including creating a new private GitHub
    repository via the 'gh' CLI.

.PARAMETER ProjectName
    The name of the project folder to be created.

.PARAMETER ProjectType
    The type of project, which determines the root directory.
    Must match a key in the $global:ProjectTypeRoots hashtable (e.g., 'Personal', 'Work').

.PARAMETER GitHub
    Optional. Specify 'public' or 'private' to create a new GitHub repo,
    or provide a full remote URL (e.g., 'git@github.com:user/repo.git') to link an existing repo.

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
    New-PyProject -ProjectName "DataAnalysis" -ProjectType "Work" -GitHub "git@github.com:user/repo.git"

.EXAMPLE
    New-PyProject -ProjectName "MyCliTool" -ProjectType "Personal" -GitHub "private" -OpenInCode

#>

# Script-scoped cache for available project types to avoid redundant lookups.
$Script:AvailableProjectTypes = $global:ProjectTypeRoots.Keys

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


function New-PyProject {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true, HelpMessage = "The name of the project folder.")]
        [string]$ProjectName,

        [Parameter(Mandatory = $true, HelpMessage = "The project type (e.g., 'Personal', 'Work'). Must match a key in your $global:ProjectTypeRoots.")]
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

        [Parameter(Mandatory = $false, HelpMessage = "Specify 'public', 'private' to create a new GitHub repo, or provide a full remote URL.")]
        [ValidateScript({
            $validInputs = @('public', 'private')
            $urlPattern = '^(https|git)@github\.com[:/].+\.git$'
            if (($_ -in $validInputs) -or ($_ -match $urlPattern)) {
                $true
            } else {
                throw "Invalid value for -GitHub. Must be 'public', 'private', or a valid GitHub remote URL (e.g., 'git@github.com:user/repo.git')."
            }
        })]
        [string]$GitHub,

        [Parameter(Mandatory = $false, HelpMessage = "If present, opens the new project in Visual Studio Code.")]
        [switch]$OpenInCode,

        [Parameter(Mandatory = $false, HelpMessage = "Specify a Python version to use (requires pyenv). Defaults to your global pyenv version.")]
        [string]$PythonVersion,

        [Parameter(Mandatory = $false, HelpMessage = "Path to a requirements.txt file to install after venv creation.")]
        [string]$Requirements
    )

    # --- Configuration & Path Setup ---
    # Get the root directory for the specified project type.
    $ProjectsRootDir = $global:ProjectTypeRoots[$ProjectType]

    if (-not $ProjectsRootDir -or -not (Test-Path -Path $ProjectsRootDir -PathType Container)) {
        Write-Error "Project root directory for type '$ProjectType' ('$ProjectsRootDir') is not defined or does not exist. Ensure the path in `$global:ProjectTypeRoots is correct."
        return
    }
    $NewProjectPath = Join-Path -Path $ProjectsRootDir -ChildPath $ProjectName

    # --- Resolve Optional Paths ---
    # Resolve the requirements path BEFORE changing directory to avoid ambiguity with relative paths.
    $resolvedRequirementsPath = $null
    if ($PSBoundParameters.ContainsKey('Requirements')) {
        $resolvedRequirementsPath = Resolve-Path -LiteralPath $Requirements -ErrorAction SilentlyContinue
        if (-not $resolvedRequirementsPath) {
            # Fail fast if the user specifies a requirements file that does not exist.
            throw "ERROR: The specified requirements file could not be found at '$Requirements'."
        }
    }

    # --- Pre-flight Checks ---
    # Check to see if pyenv is installed
    $requiredCommands = @("git", "pyenv")
    # Add 'gh' to required commands only if we are creating a new repo
    if ($PSBoundParameters.ContainsKey('GitHub') -and $GitHub -in @('public', 'private')) {
        $requiredCommands += "gh"
    }
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

    # Create subdirectories
    Write-Host "-> Creating subdirectories..."
    @("scripts", "output", "data", "notebooks") | ForEach-Object { New-Item -ItemType Directory -Name $_ } | Out-Null
    Write-Host "-> Subdirectories created successfully"

    # Create README.md
    Write-Host "-> Creating README.md..."
    # Creates a simple README with the project name as a level 1 heading.
    "# $ProjectName" | Out-File -FilePath "README.md" -Encoding utf8
    # --- Git Setup ---
    # Get the profile root path to find template files
    $functionFile = (Get-Command New-PyProject).Source
    $profileRoot = Split-Path -Path (Split-Path -Path $functionFile -Parent) -Parent

    Write-Host "-> Initializing Git repository and creating .gitignore..."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "init" -ErrorMessage "Failed to initialize Git repository."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "branch", "-M", "main" -ErrorMessage "Failed to rename default branch to 'main'."

    # Copy the standard Python .gitignore file from the templates folder in root folder of root folder for New-PyProject.ps1 
    $GitignoreTemplatePath = Join-Path -Path $profileRoot -ChildPath "templates\.gitignore_python"
    if (Test-Path $GitignoreTemplatePath) {
        Copy-Item -Path $GitignoreTemplatePath -Destination .\.gitignore
    }
    else {
        Write-Warning "Could not find .gitignore template at '$GitignoreTemplatePath'. Creating a minimal .gitignore file."
        # Create a basic .gitignore to at least ignore the venv folder
        ".venv/" | Out-File -FilePath .\.gitignore -Encoding utf8
    }

    # Insert MIT LICENSE
    Write-Host "-> Inserting MIT License..."
    $LicenseTemplatePath = Join-Path -Path $profileRoot -ChildPath "LICENSE"
    if (Test-Path $LicenseTemplatePath) {
        Copy-Item -Path $LicenseTemplatePath -Destination "LICENSE"
    }
    else {
        Write-Warning "Could not find LICENSE template at '$LicenseTemplatePath'."
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

    # --- Initial Commit and Remote ---
    Write-Host "-> Staging files for initial commit..."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "add", "." -ErrorMessage "Failed to stage files with 'git add'."
    private:Invoke-CommandOrThrow -Command "git" -Arguments "commit", "-m", "Initial commit: project structure and venv setup" -ErrorMessage "Failed to create initial commit. Is your git user.name and user.email configured?"

    if ($PSBoundParameters.ContainsKey('GitHub')) {
        if ($GitHub -in @('public', 'private')) {
            Write-Host "-> Creating new $GitHub GitHub repository '$ProjectName' with MIT license and setting remote..."
            # The 'gh' command will create the repo and add the 'origin' remote.
            private:Invoke-CommandOrThrow -Command "gh" -Arguments "repo", "create", $ProjectName, "--$GitHub", "--license", "mit", "--source=.", "--remote=origin" -ErrorMessage "Failed to create GitHub repository with 'gh'. Is the GitHub CLI authenticated? (run 'gh auth login')"
        }
        else {
            # The value is a URL, so we add it as a remote
            Write-Host "-> Adding GitHub remote: $GitHub"
            private:Invoke-CommandOrThrow -Command "git" -Arguments "remote", "add", "origin", $GitHub -ErrorMessage "Failed to add GitHub remote."
        }
    }

    # --- Final Instructions ---
    Write-Host "`nProject '$ProjectName' created successfully!" -ForegroundColor Green
    Write-Host "Next steps:"
    Write-Host "1. Activate your venv: " -NoNewline; Write-Host ".\.venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    if ($PSBoundParameters.ContainsKey('GitHub')) {
        Write-Host "2. Push to GitHub: " -NoNewline; Write-Host "git push -u origin main" -ForegroundColor Yellow
    }

    # --- Open in VS Code if requested ---
    if ($OpenInCode) {
        Write-Host "`nOpening project in Visual Studio Code..." -ForegroundColor Cyan
        code .
    }

}
