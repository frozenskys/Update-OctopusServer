# Update Octopus Server

## Synopsis
Handy script to orchestrate the steps necessary to upgrade an Octopus Server

## Usage

Simplest option (32 bit, latest version)
```PowerShell
.\Update-OctopusServer.ps1 -OctopusApiKey "API-XXXXXXXXXXXXXXXXXXXXXXXXXXX"
```

Specify version and bitness
```PowerShell
.\Update-OctopusServer.ps1 -OctopusApiKey "API-XXXXXXXXXXXXXXXXXXXXXXXXXXX" -Version "3.4.9" -Use64Bit
```

Use a pre-downloaded MSI
```PowerShell
.\Update-OctopusServer.ps1 -OctopusApiKey "API-XXXXXXXXXXXXXXXXXXXXXXXXXXX" -OctopusMsiPath "C:\Installers\Octopus\Octopus.3.4.9-x64.msi"
```

## Description
The Octopus team have published a recommended list of steps for [updating an Octopus Server](http://docs.octopusdeploy.com/display/OD/Upgrading+from+Octopus+3.x#UpgradingfromOctopus3.x-UpgradingOctopusServerUpgradingOctopusServer). 

This script will carry out the update steps (plus a couple of extras) allowing you to update in one step.

At a high level this script will:
- Download the Octopus Server MSI if necessary, getting the latest version is no version is specified (more info below)
- Put Octopus into Maintenance Mode
- Stop any Octopus Server Windows Services
- Backup your Octopus master key to a text file
- Initiate a SQL backup of your Octopus database
- Backup and compress your Octopus home directory
- Install the Octopus MSI
- Start Octopus Server Windows Services

To get the Octopus MSI the script pulls the list of versions from the [Octopus previous releases page](https://octopus.com/downloads/previous) and substitutes the version in to a templated link, adding the -x64 segment if specified, which is then downloaded.

## History
- 2016-09-30 - Initial Commit

## Known Issues
- If the Internet Explorer initial setup has not been run MSI links may not be retrieved

## Acknowledgements
- Thanks to [Dalmiro](https://github.com/Dalmirog) from Octopus for answering a couple of questions for me.
  - And for creating [OctoPosh](https://github.com/Dalmirog/OctoPosh) which really helped me out with the maintenance mode functions. 

## Notes / Requirements
- This script is intended to update from version 3.x. If you are upgrading from an earlier version please refer to [Octopus' upgrade documentation](http://docs.octopusdeploy.com/display/OD/Upgrading)
- Requires PowerShell 4.0 or greater.
- Requires the script to be run as an Administrator.
- Requires an Octopus API key issued to a user in the Administrator role.
- If you pass OctopusMsiPath and Version the version will be ignored in favour of OctopusMsiPath.
- I'm in no way affiliated with the Octopus team, just a big fan of their work.

## License
See the [LICENSE](LICENSE) file for license rights and limitations (MIT).