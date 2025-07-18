<#PSScriptInfo
 
.VERSION 1.0
 
.GUID cd5933fe-64ec-49ff-b50b-5a9a27ff54d9
 
.AUTHOR Michael Niehaus
 
.COMPANYNAME Microsoft
 
.COPYRIGHT
 
.TAGS Windows AutoPilot
 
.LICENSEURI
 
.PROJECTURI
 
.ICONURI
 
.EXTERNALMODULEDEPENDENCIES
 
.REQUIREDSCRIPTS
 
.EXTERNALSCRIPTDEPENDENCIES
 
.RELEASENOTES
Version 1.0: Original published version.
#>

<#
.SYNOPSIS
This script will build a list of serial numbers and hardware hashes pulled from ConfigMgr inventory and write them to a CSV file so they can be imported into Intune to define the devices to Windows Autopilot.
 
MIT LICENSE
 
Copyright (c) 2020 Microsoft
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
.DESCRIPTION
This script uses WMI to retrieve the serial number and hardware hash information from a ConfigMgr site server, creating a CSV file that can be imported into Intune to register the devices with Windows Autopilot. Note that it is normal for the resulting CSV file to not collect a Windows Product ID (PKID) value since this is not required to register a device. Only the serial number and hardware hash will be populated.
.PARAMETER Name
The names of a server hosting the ConfigMgr provider (assuming the local server by default).
.PARAMETER SiteCode
The three-character ConfigMgr site code for the specified ConfigMgr server (or local server).
.PARAMETER OutputFile
The name of the CSV file to be created with the details for the computers. If not specified, the details will be returned to the PowerShell pipeline.
.PARAMETER Credential
Credentials that should be used when connecting to a remote ConfigMgr provider (not used when gathering info from the local computer).
.PARAMETER GroupTag
An optional tag value that should be included in a CSV file that is intended to be uploaded via Intune.
.PARAMETER Force
A flag that indicates to write the hardware hash to the CSV file even if the serial number for the device cannot be found.
 
.EXAMPLE
.\Get-CMAutopilotHashes.ps1 -SiteCode PRI -OutputFile .\Hashes.csv
.EXAMPLE
.\Get-CMAutopilotHashes.ps1 -SiteCode PRI -ComputerName CMSERVER -Credential $PSCred -OutputFile .\Hashes.csv
 
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory=$False)][alias("DNSHostName","ComputerName","Computer")] [String] $Name = "localhost",
    [Parameter(Mandatory=$True)] [String] $SiteCode = "",
    [Parameter(Mandatory=$False)] [System.Management.Automation.PSCredential] $Credential = $null,
    [Parameter(Mandatory=$False)] [String] $GroupTag = "",
    [Parameter(Mandatory=$False)] [String] $OutputFile = "",
    [Parameter(Mandatory=$False)] [Switch] $Force = $false
)
Begin
{
    # Initialize empty list
    $computers = @()
}

Process
{
    # Get a CIM session
    if ($Name -eq "localhost") {
        $session = New-CimSession
    }
    else
    {
        $session = New-CimSession -ComputerName $Name -Credential $Credential
    }

    # Get the serial numbers for all devices
    $devices = Get-CimInstance -CimSession $session -Namespace "root\sms\site_$SiteCode" -ClassName SMS_G_SYSTEM_PC_BIOS

    # Get all the hardware hashes
    $hashes = Get-CimInstance -CimSession $session -Namespace "root\sms\site_$SiteCode" -ClassName SMS_G_System_MDM_DEVDETAIL_EXT01

    # Build the list
    $hashes | % {
        # Save the current hash
        $hash = $_

        # Find the matching serial number for this hash
        $dev = $devices | ? { $_.ResourceId -eq $hash.ResourceId }
        if (-not $dev) {
            Write-Warning "Device serial number not found for $($hash.ResourceId)"
        }

        # Create a pipeline object
        if ($dev -or $force) {

            $c = New-Object psobject -Property @{
                "Device Serial Number" = $dev.SerialNumber
                "Windows Product ID" = ""
                "Hardware Hash" = $hash.DeviceHardwareData
            }
            
            if ($GroupTag -ne "")
            {
                Add-Member -InputObject $c -NotePropertyName "Group Tag" -NotePropertyValue $GroupTag
            }

            # If no output file, just pass the object to the pipeline. Otherwise, add it to the list.
            if ($OutputFile -eq "")
            {
                $c
            }
            else
            {
                $computers += $c
            }
        }
    }

    Remove-CimSession $session

}

End
{
    if ($OutputFile) {
        # Write to an appropriately-formatted file (Intune is a little picky)
        if ($GroupTag -ne "")
        {
            $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash", "Group Tag" | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''} | Out-File $OutputFile
        }
        else
        {
            $computers | Select "Device Serial Number", "Windows Product ID", "Hardware Hash" | ConvertTo-CSV -NoTypeInformation | % {$_ -replace '"',''} | Out-File $OutputFile
        }
        Write-Host "$($computers.Count) hashes written to output file $OutputFile"
    }
