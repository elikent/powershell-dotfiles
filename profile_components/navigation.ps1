# --- Quick Navigation ---
# These functions help you jump to common folders quickly.
# They rely on global variables defined in the main profile.
 
# Internal helper function to avoid repeating the Test-Path/Set-Location logic.
# The 'private:' scope is a convention to indicate it's not for direct use.
function private:Invoke-SetLocation {
    param([string]$Path)
 
    if (Test-Path -Path $Path -PathType Container) {
        Set-Location -Path $Path
    }
    else {
        Write-Warning "Directory not found: $Path"
    }
}
 
function Set-LocationToDownloads {
    private:Invoke-SetLocation -Path (Join-Path $HOME "Downloads")
}
function Set-LocationToPersonalProjects {
    private:Invoke-SetLocation -Path $global:ProjectTypeRoots.Personal
}
function Set-LocationToWorkProjects {
    private:Invoke-SetLocation -Path $global:ProjectTypeRoots.Work
}

# A dynamic function to navigate to any project by name.
function Set-Project {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The name of the project to navigate to.")]
        [string]$ProjectName
    )

    # Iterate over the configured project root directories defined in the main profile.
    # This is more explicit and robust than searching for variables by name.
    foreach ($BasePath in $global:ProjectTypeRoots.Values) {
        $FullPath = Join-Path -Path $BasePath -ChildPath $ProjectName
        if (Test-Path -Path $FullPath) {
            Set-Location -Path $FullPath
            return # Exit the function once the project is found.
        }
    }

    # If the loop completes without finding the project, show an error.
    Write-Error "Project '$ProjectName' not found in any of your project directories."
}

# --- Aliases (Shortcuts) ---
# Simple shortcuts for the functions above and for Git.
Set-Alias -Name "dl"     -Value "Set-LocationToDownloads"
Set-Alias -Name "proj-p" -Value "Set-LocationToPersonalProjects"
Set-Alias -Name "proj-w" -Value "Set-LocationToWorkProjects"
Set-Alias -Name "go"     -Value "Set-Project"
Set-Alias -Name "gco"    -Value "git checkout"
Set-Alias -Name "gst"    -Value "git status"

# --- Argument Completer for Set-Project ---
# This block enables dynamic tab completion for the -ProjectName parameter of the Set-Project function.
# When you type 'go <tab>', it will suggest project names found within your configured project roots.
Register-ArgumentCompleter -CommandName 'Set-Project' -ParameterName 'ProjectName' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    # Collect the names of all subdirectories from each project root path.
    $projectNames = foreach ($rootPath in $global:ProjectTypeRoots.Values) {
        # Ensure the root path exists before trying to list items.
        if (Test-Path $rootPath) {
            Get-ChildItem -Path $rootPath -Directory | Select-Object -ExpandProperty Name
        }
    }

    # Filter the collected names based on what the user has already typed and return them as completion results.
    $projectNames | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
