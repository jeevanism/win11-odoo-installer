#Requires -Version 5.1

function Write-Styled-Host {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = "White",

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$BackgroundColor = "Black"
    )
    
    $OriginalForegroundColor = $Host.UI.RawUI.ForegroundColor
    $OriginalBackgroundColor = $Host.UI.RawUI.BackgroundColor
    
    $Host.UI.RawUI.ForegroundColor = $ForegroundColor
    $Host.UI.RawUI.BackgroundColor = $BackgroundColor
    
    Write-Host $Message
    
    $Host.UI.RawUI.ForegroundColor = $OriginalForegroundColor
    $Host.UI.RawUI.BackgroundColor = $OriginalBackgroundColor
}
<#
.SYNOPSIS
    An installer script for setting up a local Odoo development environment on Windows 11.
.DESCRIPTION
    This script handles prerequisites, Git cloning Odoo source code, Python virtual environment creation using 'uv',
    dependency installation with a fallback for compilation errors (like libsass), and configuration file generation.
.NOTES
    Requires Git and PowerShell 5.1+. Assumes 'Write-Styled-Host' function is defined to provide colored output.
.AUTHOR
    CodeWasher@jeevanism.com
    https://github.com/jeevanism/win-odoo-installer
    
#>

# ==============================================================================
# Global Configuration
# ==============================================================================

# Map Odoo versions to required Python versions (adjust as needed)
$OdooVersions = @{
    "19.0" = "3.12";
    "18.0" = "3.12";
    "17.0" = "3.11";
    "16.0" = "3.10";
    # "15.0" = "3.8"; -- not supported yet
    # "14.0" = "3.8"; -- not supported yet 
}

# Source URL for Odoo repository
$OdooRepoUrl = "https://github.com/odoo/odoo.git"

# Raw content URL for downloading requirements.txt (used before clone)
$OdooRepoRawUrlTemplate = "https://raw.githubusercontent.com/odoo/odoo/{0}/requirements.txt"

# Fallback Wheel Configuration for Libsass (to bypass MSVC compiler errors)
$LibsassWheelUrl = 'https://raw.githubusercontent.com/jeevanism/win-odoo-installer/main/wheels/libsass/libsass-0.20.1-cp310-cp310-win_amd64.whl'
$LibsassWheelName = 'libsass-0.20.1-cp310-cp310-win_amd64.whl'


function Check-Prerequisites {
    Write-Styled-Host "Step 1: Checking prerequisites (Git, uv)..." -ForegroundColor "Cyan"
    # Check for Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Styled-Host "Error: Git is not installed or not in PATH." -ForegroundColor "Red"
        Write-Styled-Host "--------------------------------------------------------------------------------" -ForegroundColor "Red"
        Write-Styled-Host "                 *** ACTION REQUIRED ***" -ForegroundColor "Red"
        Write-Styled-Host "Please install Git manually from the official website:" -ForegroundColor "White"
        Write-Styled-Host "--> https://git-scm.com/" -ForegroundColor "DarkYellow"
        Write-Styled-Host " " -ForegroundColor "Red"
        Write-Styled-Host "TROUBLESHOOTING TIP (If Git is installed but still not found):" -ForegroundColor "Red"
        Write-Styled-Host "1. Close and reopen your PowerShell terminal." -ForegroundColor "White"
        Write-Styled-Host "2. If that fails, manually add 'C:\Program Files\Git\cmd' to your user or system PATH environment variables." -ForegroundColor "White"
        Write-Styled-Host "--------------------------------------------------------------------------------" -ForegroundColor "Red"
        exit 1 # Exit script if Git is missing
    } 
    
    # Check for 'uv' (or 'pip' or 'python' - 'uv' is used for venv creation)
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Styled-Host "Warning: 'uv' (the Python package installer/virtual env manager) is not installed." -ForegroundColor "Yellow"
        Write-Styled-Host "Attempting to install 'uv' via 'pip' (assuming Python is in PATH)..." -ForegroundColor "Yellow"
        
        # NOTE: This assumes 'pip' is accessible. If not, the user must install uv manually.
        try {
            # Use 'pip' from the user's base Python environment to install 'uv'
            pip install uv
            Write-Styled-Host " [OK] 'uv' installed successfully." -ForegroundColor "Green"
        }
        catch {
            Write-Styled-Host "Error: Failed to install 'uv'. Please install it manually: pip install uv" -ForegroundColor "Red"
            exit 1
        }
    }
    
    Write-Styled-Host " [OK] All prerequisites found (Git and uv)." -ForegroundColor "Green"

} 


# New function added to allow the rest of the script to run
function Select-Odoo-Version {
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Versions = $OdooVersions
    )
    
    Write-Styled-Host "Step 2: Select Odoo Version" -ForegroundColor "Cyan"
    $i = 1
    $VersionMap = @{}

    foreach ($odoo in $Versions.GetEnumerator() | Sort-Object Name -Descending) {
        Write-Styled-Host " [$i] Odoo $($odoo.Name) (Python $($odoo.Value))" -ForegroundColor "White"
        $VersionMap.Add($i, $odoo.Name)
        $i++
    }

    $selection = Read-Host -Prompt "Enter the number for the Odoo version you want to install (e.g., 1)"
    
    while (-not ($VersionMap.ContainsKey([int]$selection))) {
        Write-Styled-Host "Invalid selection. Please enter a valid number." -ForegroundColor "Red"
        $selection = Read-Host -Prompt "Enter the number for the Odoo version you want to install"
    }

    $selectedVersion = $VersionMap[[int]$selection]
    Write-Styled-Host " [INFO] Selected Odoo Version: $selectedVersion" -ForegroundColor "Green"
    return $selectedVersion
}


function Download-Requirements-Only {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OdooVersion,
        [Parameter(Mandatory = $true)]
        [string]$CloneDir 
    )

    Write-Styled-Host "Step 3 (PREP): Downloading requirements.txt and creating mock directories." -ForegroundColor "Cyan"

    $url = $OdooRepoRawUrlTemplate -f $OdooVersion
    $targetFile = Join-Path -Path $CloneDir -ChildPath "requirements.txt"

    # 1. Create the clone directory if it doesn't exist
    if (-not (Test-Path $CloneDir)) {
        New-Item -Path $CloneDir -ItemType Directory | Out-Null
    }

    # 2. Download the requirements file
    Write-Host "Downloading requirements.txt from: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $targetFile
        if (-not (Test-Path $targetFile)) {
            throw "Download failed: File '$targetFile' not found after Invoke-WebRequest."
        }
    }
    catch {
        Write-Styled-Host "Error: Failed to download requirements.txt for Odoo $OdooVersion. Check the URL and version." -ForegroundColor "Red"
        throw $_.Exception.Message
    }

    Write-Styled-Host " [OK] requirements.txt downloaded to '$targetFile'." -ForegroundColor "Green"
    
    # 3. Create directories for addons 
    $odooInternalAddons = Join-Path -Path $CloneDir -ChildPath "odoo\addons"
    $odooExternalAddons = Join-Path -Path $CloneDir -ChildPath "addons"
    
    if (-not (Test-Path $odooInternalAddons)) { New-Item -Path $odooInternalAddons -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $odooExternalAddons)) { New-Item -Path $odooExternalAddons -ItemType Directory -Force | Out-Null }

    Write-Styled-Host " [INFO] Created mock addons directories for configuration." -ForegroundColor "DarkGray"
}


function Generate-Odoo-Conf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OdooVersion,
        [Parameter(Mandatory = $true)]
        [string]$BaseInstallPath,
        [Parameter(Mandatory = $true)]
        [string]$OdooCloneDir 
    )

    Write-Styled-Host "Step 6: Generating odoo.conf file..." -ForegroundColor "Cyan"

    # Calculate ports: e.g., 17.0 -> 8017
    $MajorVersion = ($OdooVersion -split '\.')[0]
    $HttpPort = "80" + $MajorVersion
    $LongpollingPort = "8072"
    
    # Paths are relative to BaseInstallPath (the new odoo-XX folder)
    $confFilePath = Join-Path -Path $BaseInstallPath -ChildPath "odoo.conf"
    $dataDir = Join-Path -Path $BaseInstallPath -ChildPath "data"

    # Core Odoo Addons Paths
    $OdooCoreExternalAddons = Join-Path -Path $OdooCloneDir -ChildPath "addons"
    $OdooCoreInternalAddons = Join-Path -Path $OdooCloneDir -ChildPath "odoo\addons"


    # Custom Addons Path
    $customAddonsDir = Join-Path -Path $BaseInstallPath -ChildPath "custom-addons"
    
    # Create data and custom-addons directories if they don't exist (inside BaseInstallPath)
    if (-not (Test-Path $dataDir)) { New-Item -Path $dataDir -ItemType Directory | Out-Null }
    if (-not (Test-Path $customAddonsDir)) { New-Item -Path $customAddonsDir -ItemType Directory | Out-Null }

    # Generate addons_path using forward slashes (Unix style) for config file reliability
    $pathArray = @(
        $($OdooCoreInternalAddons -replace '\\','/'),
        $($OdooCoreExternalAddons -replace '\\','/'),
        $($customAddonsDir -replace '\\', '/')
    )
    $addonsPath = $pathArray -join ','
    

    $confContent = @"
[options]

# --- Paths ---
data_dir = $($dataDir -replace '\\','/')
addons_path = $addonsPath

# This is the password that allows database operations:
admin_passwd = admin

# --- Connection Settings ---
http_port = $HttpPort
xmlrpc_port = $HttpPort
longpolling_port = $LongpollingPort

# --- Database Connection (Requires PostgreSQL) ---
db_host = False
db_port = False
db_user = False
db_password = False
db_maxconn = 64



# --- Development & Logging ---
log_level = info
list_db = True
proxy_mode = False
debug_mode = False
without_demo = False
workers = 2
server_wide_modules = web
"@

    Set-Content -Path $confFilePath -Value $confContent -Encoding Ascii
    Write-Styled-Host "  [OK] odoo.conf generated successfully at '$confFilePath'." -ForegroundColor "Green"
}

# Clone the Odoo Source code as per User Selection 
function Do-Git-Clone {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OdooVersion,
        [Parameter(Mandatory = $true)]
        [string]$CloneDir
    )

    Write-Styled-Host "Step 7 (FINAL): Cloning Odoo $OdooVersion repository..." -ForegroundColor "Cyan"

    # Remove the mock files/folders but keep the $CloneDir folder itself
    Write-Styled-Host " [INFO] Removing temporary files/folders to prepare for Git clone..." -ForegroundColor "DarkGray"
    
    # Remove contents of $CloneDir but ignore errors if files are locked (unlikely here)
    Remove-Item -Path "$CloneDir\*" -Recurse -Force -ErrorAction SilentlyContinue 
    Remove-Item -Path "$CloneDir\.*" -Recurse -Force -ErrorAction SilentlyContinue 
    
    # Perform clone
    $gitCommand = "git clone --branch $OdooVersion --single-branch $OdooRepoUrl `"$CloneDir`""
    Write-Host "Executing: $gitCommand"
    
    # Change location to the parent directory to run the clone command correctly
    Set-Location (Split-Path -Path $CloneDir -Parent) 
    
    Invoke-Expression $gitCommand
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone Odoo repository (branch $OdooVersion). Git failed with exit code $LASTEXITCODE."
    }
    
    # Change back into the clone directory for final checks
    Set-Location $CloneDir
    
    Write-Styled-Host " [OK] Odoo $OdooVersion cloned successfully to '$CloneDir'." -ForegroundColor "Green"
}


try {
    $originalLocation = Get-Location
    Check-Prerequisites

    $selectedOdooVersion = Select-Odoo-Version
    $requiredPythonVersion = $OdooVersions[$selectedOdooVersion]
    

    $MajorVersion = ($selectedOdooVersion -split '\.')[0]
    $parentInstallFolderName = "odoo-$MajorVersion" # e.g., odoo-19
    $parentInstallDir = Join-Path -Path $originalLocation -ChildPath $parentInstallFolderName
    
    # The clone directory for the source code
    $cloneDir = Join-Path -Path $parentInstallDir -ChildPath "odoo-src"
    
    Write-Styled-Host "Setting up directory structure in '$parentInstallDir'..." -ForegroundColor "Cyan"
    
    # Create the new parent directory
    if (-not (Test-Path $parentInstallDir)) {
        New-Item -Path $parentInstallDir -ItemType Directory | Out-Null
    }
    
    # 1. Clean up existing source dir and download requirements.txt/create mock dirs
    if (Test-Path $cloneDir) {
        Write-Styled-Host "Removing existing test source directory '$cloneDir' contents for a clean install." -ForegroundColor "Yellow"
        Remove-Item -Path $cloneDir -Recurse -Force
    }

    # Download requirements.txt and create mock folders 
    Download-Requirements-Only -OdooVersion $selectedOdooVersion -CloneDir $cloneDir
    
    # Change location to the PARENT directory to create .venv there.
    Set-Location $parentInstallDir 

    # 2. Set up Python VENV (requires us to be in $parentInstallDir)
    Write-Styled-Host "Step 4: Setting up Python environment..." -ForegroundColor "Cyan"
    $venvCommand = "uv venv --python $requiredPythonVersion"
    Write-Host "Executing: $venvCommand"
    Invoke-Expression $venvCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Python virtual environment. Ensure Python $requiredPythonVersion is available via 'uv'."
    }
    Write-Styled-Host " [OK] Python virtual environment created with Python $requiredPythonVersion." -ForegroundColor "Green"

    Write-Styled-Host "Step 4.5: Installing 'setuptools' (required by Odoo runtime)..." -ForegroundColor "Cyan"
    $setuptoolsInstallCommand = "uv pip install setuptools"
    Write-Host "Executing: $setuptoolsInstallCommand"
    Invoke-Expression $setuptoolsInstallCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install setuptools. Cannot continue."
    }
    Write-Styled-Host " [OK] 'setuptools' installed." -ForegroundColor "Green"
    # 3. Install dependencies (requires requirements.txt to be in $cloneDir)
    Set-Location $cloneDir 
    
    Write-Styled-Host "Step 5: Installing dependencies from requirements.txt..." -ForegroundColor "Cyan"
    $requirementsFile = ".\requirements.txt"
    
    # 1. Attempt the main installation first.
    $initialInstallCommand = "uv pip install -r $requirementsFile"
    Write-Host "Executing initial install: $initialInstallCommand"
    Invoke-Expression $initialInstallCommand
    
    if ($LASTEXITCODE -ne 0) {
        # Fallback logic for libsass, etc.
        Write-Styled-Host "`nWarning: Initial dependency installation failed ($LASTEXITCODE). Attempting compiler fallback..." -ForegroundColor "Yellow"
        Write-Styled-Host "### COMPILER FALLBACK ACTIVATED ###" -ForegroundColor "Yellow"
        
        # Download and install the wheel
        Write-Styled-Host "Attempting to download and install pre-built 'libsass' wheel..." -ForegroundColor "Yellow"
        try {
            Invoke-WebRequest -Uri $LibsassWheelUrl -OutFile $LibsassWheelName
            $installWheelCommand = "uv pip install --no-deps --no-build-isolation .\$LibsassWheelName"
            Invoke-Expression $installWheelCommand
        }
        catch {
            throw "Failed to download or install the pre-built 'libsass' wheel."
        }
        Write-Styled-Host " [OK] Libsass wheel installed successfully." -ForegroundColor "Green"

        # Re-run the main installation
        Write-Styled-Host "Re-running dependency installation for remaining packages..." -ForegroundColor "Yellow"
        $reinstallCommand = "uv pip install -r $requirementsFile --upgrade" 
        Write-Host "Executing re-install with UTF-8 encoding: $reinstallCommand"
        $env:PYTHONIOENCODING = 'utf-8'
        Invoke-Expression $reinstallCommand
        $env:PYTHONIOENCODING = $null
        
        if ($LASTEXITCODE -ne 0) {
            throw "Remaining dependencies failed to install after libsass fix."
        }
        Write-Styled-Host " [OK] All dependencies installed successfully via manual intervention." -ForegroundColor "Green"
    }
    else {
        Write-Styled-Host " [OK] Dependencies installed successfully." -ForegroundColor "Green"
    }

    # 4. Generate Odoo.conf 
    Set-Location $parentInstallDir
    Generate-Odoo-Conf -OdooVersion $selectedOdooVersion -BaseInstallPath $parentInstallDir -OdooCloneDir $cloneDir

    # 5.Perform the actual Git Clone
    Do-Git-Clone -OdooVersion $selectedOdooVersion -CloneDir $cloneDir
    
    # --- Summary ---
    Write-Styled-Host "------------------- Odoo Setup Complete -------------------" -ForegroundColor "Magenta"
    Write-Styled-Host " Installation Directory: $parentInstallDir" -ForegroundColor "White"
    Write-Styled-Host " Odoo Version:      $selectedOdooVersion" -ForegroundColor "White"
    Write-Styled-Host " Odoo Source Path:    $cloneDir" -ForegroundColor "White"
    Write-Styled-Host " Custom Addons Path: $(Join-Path -Path $parentInstallDir -ChildPath 'custom-addons')" -ForegroundColor "White"
    Write-Styled-Host " Config File:      $(Join-Path -Path $parentInstallDir -ChildPath 'odoo.conf')" -ForegroundColor "White"
    Write-Styled-Host " HTTP Port:       $HttpPort (Longpolling: $LongpollingPort)" -ForegroundColor "White"
    Write-Styled-Host "-----------------------------------------------------------" -ForegroundColor "Magenta"
    Write-Styled-Host "To start Odoo, run the following command from this new directory ($parentInstallDir):" -ForegroundColor "Yellow"
    
    # Generate the robust startup command
    $startCommand = "& '$parentInstallDir\.venv\Scripts\python.exe' '$cloneDir\odoo-bin' -c odoo.conf"
    Write-Styled-Host " $startCommand" -ForegroundColor "DarkYellow"
    Write-Host " (NOTE: Remember to set up and configure your PostgreSQL database before starting.)" -ForegroundColor "Red"
    $step1 = "cd $parentInstallDir"
    Write-Styled-Host " 1. Move into the Odoo directory:" -ForegroundColor "White"
    Write-Styled-Host " -> $step1" -ForegroundColor "DarkYellow"
    $step2 = ".\.venv\Scripts\Activate.ps1"
    Write-Styled-Host " 2. Activate the Python Virtual Environment (venv):" -ForegroundColor "White"
    Write-Styled-Host " -> $step2" -ForegroundColor "DarkYellow"
    $step3 = "python.exe .\odoo-src\odoo-bin -c .\odoo.conf"
    Write-Styled-Host " 3. Run the Odoo server using the generated config file:" -ForegroundColor "White"
    Write-Styled-Host " -> $step3" -ForegroundColor "DarkYellow"

}
catch {
    Write-Styled-Host "An error occurred during installation:" -ForegroundColor "Red"
    Write-Styled-Host $_.Exception.Message -ForegroundColor "Red"
    exit 1
} 
finally {
    # Ensure we return to the starting directory on exit
    if ($originalLocation -and (Get-Location) -ne $originalLocation) {
        Set-Location $originalLocation
    }
} 