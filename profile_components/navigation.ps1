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
    private:Invoke-SetLocation -Path (Join-Path $env:USERPROFILE "Downloads")
}
function Set-LocationToPersonalProjects {
    private:Invoke-SetLocation -Path $global:PersonalProjectsPath
}
function Set-LocationToWorkProjects {
    private:Invoke-SetLocation -Path $global:WorkProjectsPath
}

# A dynamic function to navigate to any project by name.
function Set-Project {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The name of the project to navigate to.")]
        [string]$ProjectName
    )

    # Dynamically find all global variables ending in 'ProjectsPath' to use as search locations.
    # An examply value of one of these variables is "D:\my-projects\personal"
    # This makes the function automatically adapts to new project roots defined in the main profile.

    # Create an array of all the global variables ending in 'ProjectsPath'.
    $SearchPaths = Get-Variable -Scope Global -Name "*ProjectsPath" -ErrorAction SilentlyContinue |
                   # Remove null or empty strings from the array 
                   Select-Object -ExpandProperty Value |
                   Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    # For each base path (eg ) in $SearchPaths, create a full path with BasePath ProjectName and check if it exists.
    foreach ($BasePath in $SearchPaths) {
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
