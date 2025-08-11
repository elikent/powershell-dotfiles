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

# Internal helper function to execute external commands and throw a terminating error on failure.
# This simplifies error handling in the main function body.
function script:Invoke-CommandOrThrow {
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

# Internal helper function to create a dynamic LICENSE file from a template.
function script:New-LicenseFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileRoot
    )

    Write-Verbose "Creating dynamic LICENSE file..."
    $LicenseTemplatePath = Join-Path -Path $ProfileRoot -ChildPath "templates\LICENSE_template"

    if (-not (Test-Path $LicenseTemplatePath)) {
        Write-Warning "LICENSE template not found at '$LicenseTemplatePath'. Skipping license creation."
        return
    }

    # Use a global variable for the copyright holder for easy configuration in the user's profile.
    # Priority: 1. $global:GitAuthorName, 2. git config user.name, 3. Fallback string.
    $copyrightHolder = $global:GitAuthorName
    if (-not $copyrightHolder) {
        # If the global var isn't set, try to get it from the git config.
        $gitUserName = (git config user.name).Trim()
        if ($gitUserName) {
            $copyrightHolder = $gitUserName
        } else { $copyrightHolder = "Your Name" } # Fallback if all else fails
    }
    $currentYear = Get-Date -Format "yyyy"

    (Get-Content $LicenseTemplatePath -Raw) -replace '\{YEAR\}', $currentYear -replace '\{COPYRIGHT_HOLDER\}', $copyrightHolder | Out-File -FilePath "LICENSE" -Encoding utf8
    Write-Verbose "LICENSE file created successfully for '$copyrightHolder' ($currentYear)."
}


function New-PyProject {
    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true, HelpMessage = "The name of the project folder.")]
        [string]$ProjectName,

        [Parameter(Mandatory = $true, HelpMessage = 'The project type (e.g., ''Personal'', ''Work''). Must match a key in your $global:ProjectTypeRoots.')]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            # Dynamically get project types from the global variable at runtime.
            $global:ProjectTypeRoots.Keys | Where-Object { $_ -like "*$wordToComplete*" }
        })]
        [ValidateScript({
            $availableTypes = $global:ProjectTypeRoots.Keys
            if ($_ -in $availableTypes) {
                $true
            } else {
                throw "Invalid ProjectType '$_'. Available types are: $($availableTypes -join ', ')"
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

    # --- Pre-flight Check for Global Configuration ---
    # This check runs when the function is called, not when the script is loaded, making it more robust.
    if (-not $global:ProjectTypeRoots -is [hashtable] -or $global:ProjectTypeRoots.Count -eq 0) {
        throw "Global configuration variable `$global:ProjectTypeRoots is not defined or is empty. Please define it in your profile as a hashtable (e.g., `$global:ProjectTypeRoots = @{ Personal = 'D:\path'}`)."
    }

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

    Write-Verbose "Setting up new Python project: $ProjectName"

    # Create the project directory and navigate into it
    New-Item -ItemType Directory -Path $NewProjectPath | Out-Null
    Set-Location $NewProjectPath

    # Create subdirectories
    Write-Verbose "Creating subdirectories..."
    @("scripts", "output", "data", "notebooks") | ForEach-Object { New-Item -ItemType Directory -Name $_ } | Out-Null
    Write-Verbose "Subdirectories created successfully."

    # Create README.md
    Write-Verbose "Creating README.md..."
    # Creates a simple README with the project name as a level 1 heading.
    "# $ProjectName" | Out-File -FilePath "README.md" -Encoding utf8
    # --- Git Setup ---
    # Get the profile root path to find template files
    $profileRoot = Split-Path -Path $PROFILE -Parent


    Write-Verbose "Initializing Git repository and creating .gitignore..."
    script:Invoke-CommandOrThrow -Command "git" -Arguments "init" -ErrorMessage "Failed to initialize Git repository."
    script:Invoke-CommandOrThrow -Command "git" -Arguments "branch", "-M", "main" -ErrorMessage "Failed to rename default branch to 'main'."

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

    # Create the LICENSE file using the helper function
    script:New-LicenseFile -ProfileRoot $profileRoot
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
    Write-Verbose "Pinning Python version to '$VersionToUse' using 'pyenv local'..."

    # Set pyenv local
    # pyenv local then 1) checks its own inventory to see if $VersionToUse is installed and
    # 2) creates the .python-version file which tells pyenv and future users which version to use for project.
    script:Invoke-CommandOrThrow -Command "pyenv" -Arguments "local", $VersionToUse -ErrorMessage "pyenv failed to set version '$VersionToUse'. Is it installed? (e.g., 'pyenv install $VersionToUse')"

    # All above worked. report.
    Write-Verbose "Creating Python virtual environment (.venv) with Python $VersionToUse..."
    # Create venv with specified python version
    script:Invoke-CommandOrThrow -Command "python" -Arguments "-m", "venv", ".venv" -ErrorMessage "Failed to create the Python virtual environment (.venv). Please check your Python installation."

    # --- Initial Dependency Installation ---
    if ($resolvedRequirementsPath) {
        Write-Verbose "Installing dependencies from '$($resolvedRequirementsPath.Path)'..."
        # Set $VenvPython as python.exe installed in venv and Directly use to run pip
        $VenvPython = Join-Path -Path $NewProjectPath -ChildPath ".venv\Scripts\python.exe"
        script:Invoke-CommandOrThrow -Command $VenvPython -Arguments "-m", "pip", "install", "-r", $resolvedRequirementsPath.Path -ErrorMessage "Failed to install dependencies from '$($resolvedRequirementsPath.Path)'. Please check the file contents and your network connection."
    }

    # --- Initial Commit and Remote ---
    Write-Verbose "Staging files for initial commit..."
    script:Invoke-CommandOrThrow -Command "git" -Arguments "add", "." -ErrorMessage "Failed to stage files with 'git add'."
    script:Invoke-CommandOrThrow -Command "git" -Arguments "commit", "-m", "Initial commit: project structure and venv setup" -ErrorMessage "Failed to create initial commit. Is your git user.name and user.email configured?"

    if ($PSBoundParameters.ContainsKey('GitHub')) {
        if ($GitHub -in @('public', 'private')) {
            Write-Verbose "Creating new $GitHub GitHub repository '$ProjectName' and setting remote..."
            # Create the empty repo on GitHub and add the 'origin' remote. The '--source' flag is removed
            # to make the subsequent push explicit and more reliable.
            script:Invoke-CommandOrThrow -Command "gh" -Arguments "repo", "create", $ProjectName, "--$GitHub", "--remote=origin" -ErrorMessage "Failed to create GitHub repository with 'gh'. Is the GitHub CLI authenticated? (run 'gh auth login')"

            Write-Verbose "Pushing initial commit to 'origin'..."
            script:Invoke-CommandOrThrow -Command "git" -Arguments "push", "-u", "origin", "main" -ErrorMessage "Failed to push initial commit to GitHub."
        }
        else {
            # The value is a URL, so we add it as a remote
            Write-Verbose "Adding GitHub remote: $GitHub"
            script:Invoke-CommandOrThrow -Command "git" -Arguments "remote", "add", "origin", $GitHub -ErrorMessage "Failed to add GitHub remote."
        }
    }

    # --- Final Instructions ---
    Write-Host "`nProject '$ProjectName' created successfully!" -ForegroundColor Green
    Write-Host "Next steps:"
    Write-Host "1. Activate your venv: " -NoNewline; Write-Host ".\.venv\Scripts\Activate.ps1" -ForegroundColor Yellow
    # Suggest pushing only when the user provided an existing remote URL, as the script
    # now handles the initial push automatically when creating a new repository.
    if ($PSBoundParameters.ContainsKey('GitHub')) {
        if ($GitHub -notmatch '^(public|private)$') {
            Write-Host "2. Push to GitHub: " -NoNewline; Write-Host "git push -u origin main" -ForegroundColor Yellow
        }
    }

    # --- Open in VS Code if requested ---
    if ($OpenInCode) {
        Write-Host "`nOpening project in Visual Studio Code..." -ForegroundColor Cyan
        code .
    }

}
