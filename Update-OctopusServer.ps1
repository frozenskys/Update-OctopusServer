<#
.SYNOPSIS
	Handy script to orchestrate the steps necessary to upgrade an Octopus Server

.DESCRIPTION
	The Octopus team have published a recommended list of steps for upgrading an Octopus server.
	This script will carry out the update steps (plus a couple of extras) allowing you to update in one step.
	At a high level this script will:
	- Download the Octopus server MSI if necessary, getting the latest version is no version is specified
	- Put Octopus into Maintenance Mode
	- Stop any Octopus server windows services (the installer will do this but not for multiple instances)
	- Backup your Octopus master key to a text file
	- Backup your Octopus database
	- Backup and compress your Octopus home directory
	- Install the Octopus MSI
	- Start Octopus server windows services (again to account for multiple instances)
	
	This script is intended to update from version 3.x. If you are upgrading from an earlier version please refer to Octopus' upgrade documentation available at http://docs.octopusdeploy.com/display/OD/Upgrading

.PARAMETER OctopusApiKey
	An API key with Administrative rights needs to be passed to enable and disable maintenance mode on the Octopus server

.PARAMETER OctopusMsiPath
	Specifies a path to an Octopus MSI that has already been downloaded.
	This is useful if your Octopus server doesn't have internet access.
	This will override any version specified.

.PARAMETER Version
	Specifies the version of the Octopus Server MSI to download based on what is available at https://octopus.com/downloads/previous

.PARAMETER Use64Bit
	Downloads the 64 bit version of the Octopus Server installer. Not specifying this will default to the 32 bit version.


.PARAMETER Help
	Displays this help as an alternative to calling "Get-Help .\Update-OctopusServer.ps1"

.EXAMPLE
  .\Update-OctopusServer.ps1 -OctopusApiKey "API-XXXXXXXXXXXXXXXXXXXXXXXXXXX"
	This is the same as running .\Update-OctopusServer.ps1 -OctopusApiKey "API-XXXXXXXXXXXXXXXXXXXXXXXXXXX" -Version latest	

.EXAMPLE
	.\Update-OctopusServer.ps1 -Version "3.4.9" -Use64Bit

.EXAMPLE
	.\Update-OctopusServer.ps1 -OctopusMsiPath "C:\Installers\Octopus\Octopus.3.4.9-x64.msi"

.NOTES
	Requires Powershell 4.0 or greater and RunAsAdministrator
	This script is intended to update from version 3.x. If you are upgrading from an earlier version please refer to Octopus' upgrade documentation available at http://docs.octopusdeploy.com/display/OD/Upgrading

.LINK
	https://github.com/rh072005/Update-OctopusServer

.LINK
	http://docs.octopusdeploy.com/display/OD/Upgrading+from+Octopus+3.x
#>

#Requires -Version 4.0
#Requires -RunAsAdministrator
[CmdletBinding()]
param($OctopusMsiPath, $Version, $OctopusApiKey, [switch]$Use64Bit, [switch]$Help)

function Install-OctopusMsi {
  param ($MsiPath)
  Write-Host "Installing Octopus Server..."
  $msiLog = "OctopusServer.msi.log"
  $msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $msiPath /quiet /l*v $msiLog" -Wait -Passthru).ExitCode
  if ($msiExitCode -ne 0){
    throw "Installation of the Octopus Server MSI failed; MSIEXEC exited with code: $msiExitCode. View the log at $msiLog"
  }
}

function Get-CurrentOctopusVersion {
  param ($OctopusServerUri)  
  return ((Invoke-WebRequest "$($OctopusServerUri)api").Content | ConvertFrom-Json).Version
}

function Get-IsOctopusInMaintenanceMode {	
  param($OctopusServerUri, $OctopusApiKey)
  $apiPath = "api/maintenanceconfiguration"
  $header = @{ "X-Octopus-ApiKey" = $OctopusApiKey }
  $maintenanceModeQuery = (Invoke-WebRequest "$($OctopusServerUri)$($apiPath)" -Headers $header).Content | ConvertFrom-Json
  return $maintenanceModeQuery.IsInMaintenanceMode
}

function Set-OctopusInMaintenanceMode {
  param($OctopusServerUri, $OctopusApiKey, $MaintenanceMode)
	If ($MaintenanceMode -eq "on"){
		$MaintenanceModeBool = $true
	} else {
		$MaintenanceModeBool = $false
	} 
  $apiPath = "api/maintenanceconfiguration"
  $header = @{ "X-Octopus-ApiKey" = $OctopusApiKey }
  $body = @{IsInMaintenanceMode=$MaintenanceModeBool} | ConvertTo-Json
  Write-Host "Switching Octopus Server maintenance mode $($MaintenanceMode)..."
  Invoke-WebRequest "$($OctopusServerUri)$($apiPath)" -Method PUT -Body $body -Headers $header | Out-Null
}

function Backup-MasterKey {
  param($OctopusServerExe, $OutputPath)
  Write-Host "Backing up master key..."
  (& $OctopusServerExe show-master-key)[2] > $OutputPath
}

function Backup-OctopusDatabase {
	param ($ConnectionString, $BackupDateStamp)
	[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null
	$connectionStringBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
	$SqlServerInstanceName = $connectionStringBuilder."Data Source"
	$OctopusDatabaseInitialCatalog = $connectionStringBuilder."Initial Catalog"
	$SqlServer = New-Object 'Microsoft.SqlServer.Management.SMO.Server' $SqlServerInstanceName
	$SqlServerName = $SqlServer.Name
	$OctopusDatabase = $SqlServer.Databases[$OctopusDatabaseInitialCatalog]
	$OctopusDatabaseName = $OctopusDatabase.Name
	$backupFilePath = "$($OctopusDatabaseName)_db_$($BackupDateStamp).bak"
	Write-Host "Backing up Octopus database..."
	pushd (Get-Location)
	Backup-SqlDatabase -ServerInstance $SqlServerName -Database $OctopusDatabaseName -BackupFile $backupFilePath
	popd
}

function Stop-OctopusServices {
  Write-Host "Stopping Octopus service(s)..."
  Get-Service | ?{$_.Name -match "Octopus" -and $_.Name -notmatch "Tentacle"} | % {Stop-Service $_.Name}
}

function Start-OctopusServices {
  Write-Host "Starting Octopus service(s)..."
  Get-Service | ?{$_.Name -match "Octopus" -and $_.Name -notmatch "Tentacle"} | % {Start-Service $_.Name}
}

function Backup-OctopusHomeDirectory {
  param ($HomeDirectory, $OutputPath)
  Write-Host "Backing up Octopus home directory..."
  if($PSVersionTable.PSVersion.Major -lt 5){
    Add-Type -Assembly "System.IO.Compression.FileSystem" | Out-Null
    [IO.Compression.ZipFile]::CreateFromDirectory($HomeDirectory, $OutputPath) | Out-Null
  } else {
    Compress-Archive -Path $HomeDirectory -DestinationPath $OutputPath | Out-Null
  }
}

function Get-OctopusMsi {
	param([string]$Version, [switch]$Use64Bit)
	if(-not ($Version)) {throw "Version number not specified in Get-OctopusMsi"}
	Write-Host "Getting Octopus version information..."	
	$previousVersionsPage = (invoke-webrequest "https://octopus.com/downloads/previous")
	$OctopusVersions = ($previousVersionsPage.links | ? {$_.href -match "/downloads/" -and $_.href -notmatch "/downloads/previous"}).innerText
	$SelectedVersion = If($Version.ToLower() -eq "latest") {$OctopusVersions[0]} else {$Version}
	$architectureFlag = If($Use64Bit) {"-x64"} 
	$MsiName = "Octopus.$($SelectedVersion)$($architectureFlag).msi"
	$LocalMsiPath = Join-Path (Get-Location) $MsiName
	$MsiUrl = "https://download.octopusdeploy.com/octopus/$($MsiName)"
	Write-Host "Downloading $($MsiUrl)..."
	(New-Object System.Net.WebClient).DownloadFile($MsiUrl, $LocalMsiPath)
	return $LocalMsiPath
}

function Update-Tentacles {	
	Write-Host "Update-Tentacles is not yet implemented!"
}

function Update-Octopus {
	param(
	  [string]$OctopusMsiPath,
	  [string]$Version,
	  [string]$OctopusApiKey,
	  [switch]$Use64Bit
	)
	
	$ErrorActionPreference = "Stop"
	pushd (Get-Location)
	Write-Host "Reading configuration data..."
	$ServerLocation = (Get-Item HKLM:\SOFTWARE\Octopus\OctopusServer | Get-Itemproperty -Name InstallLocation | Select InstallLocation).InstallLocation
	$OctopusServerConfigPath = (Get-Item HKLM:\SOFTWARE\Octopus\OctopusServer\OctopusServer | Get-Itemproperty -Name ConfigurationFilePath | Select ConfigurationFilePath).ConfigurationFilePath
	$OctopusServerExe = Join-Path $ServerLocation "Octopus.Server.exe"
	[xml]$OctopusConfig = (Get-Content $OctopusServerConfigPath)
	$OctopusServerHomeDirectory = ($OctopusConfig."octopus-settings".set | Where-Object {$_.key -eq "Octopus.Home"})."#text"
	$OctopusServerUri = ($OctopusConfig."octopus-settings".set | Where-Object {$_.key -eq "Octopus.WebPortal.ListenPrefixes"})."#text"
	$OctopusDatabaseConnectionString = ($OctopusConfig."octopus-settings".set | Where-Object {$_.key -eq "Octopus.Storage.ExternalDatabaseConnectionString"})."#text"
	$backupDateStamp = Get-Date -format yyyyMMddHHmmss

	$existingVersion = Get-CurrentOctopusVersion -OctopusServerUri $OctopusServerUri	
	Write-Host "Upgrading from version $($existingVersion)..."
	
	if((-not($OctopusMsiPath)) -and (-not($Version))){
	  Write-Host "No version has been specified, defaulting to latest..."
	  $Version = "latest"
	}
	
	if($OctopusMsiPath){
	    if(-not(Test-Path $OctopusMsiPath)){
		    throw "$OctopusMsiPath was not found!"
		  }
	} else {
		$params = @{'Version'=$Version;'Use64Bit'=$Use64Bit}
		$OctopusMsiPath = Get-OctopusMsi @params	
	}	
	
	if(-not(Get-IsOctopusInMaintenanceMode -OctopusServerUri $OctopusServerUri -OctopusApiKey $OctopusApiKey)) {
	  Set-OctopusInMaintenanceMode -OctopusServerUri $OctopusServerUri -OctopusApiKey $OctopusApiKey -MaintenanceMode "on"
	}
		
	Stop-OctopusServices
	Backup-MasterKey -OctopusServerExe $OctopusServerExe -OutputPath "masterkey_$($backupDateStamp).txt"	
	Backup-OctopusDatabase -ConnectionString $OctopusDatabaseConnectionString -BackupDateStamp $backupDateStamp
	Backup-OctopusHomeDirectory -HomeDirectory $OctopusServerHomeDirectory -OutputPath "Backup_$($backupDateStamp).zip" 
	
	Install-OctopusMsi -MsiPath $OctopusMsiPath
	Start-OctopusServices
	
  #The Octopus service takes a couple of seconds to start up
	Start-Sleep -s 5
	if(Get-IsOctopusInMaintenanceMode -OctopusServerUri $OctopusServerUri -OctopusApiKey $OctopusApiKey) {
	  Set-OctopusInMaintenanceMode -OctopusServerUri $OctopusServerUri -OctopusApiKey $OctopusApiKey -MaintenanceMode "off" | Out-Null
	}

	$newVersion = Get-CurrentOctopusVersion -OctopusServerUri $OctopusServerUri	
	Write-Host "Now running version $($newVersion)..."

	popd
	
	Write-Host "Update complete."
}

if($Help){
  Get-Help $PSCommandPath
  return
}

$params = @{'OctopusMsiPath'=$OctopusMsiPath;'Version'=$Version;'OctopusApiKey'=$OctopusApiKey;'Use64Bit'=$Use64Bit}
Update-Octopus @params
