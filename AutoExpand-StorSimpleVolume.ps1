#Requires -Version 4
#Requires -Modules @{ModuleName='Azure'; ModuleVersion='0.9.8.1'}
#Requires -RunAsAdministrator 

<# 
Script to auto-expand StorSimple volume based on configurable parameters
This is intended to run as a scheduled task or job on the file server receiving 
the iSCSI volume from StorSimple device.
For more information see 
https://superwidgets.wordpress.com/2016/04/01/powershell-script-to-auto-expand-storsimple-volume-based-on-amount-of-free-space/
Author: Sam Boutros - 29 March, 2016 - v1.0
#>


#region Input
$SubscriptionName       = 'YourSubscription Name Here'
$StorSimpleManagerName  = 'sstorsimplemanager'
$RegistrationKey        = '8764431xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx1e96'
$SSDeviceName           = 'axxxxxxxxxx01'
$SSVolumeName           = 'SamTest1-Vol'
$SubscriptionID         = '9exxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx1e'
$Notify                 = $true # $true or $false to send email notification every time expansion is triggered or performed
$Expand                 = $true # If using $false here, the script will email-notify only upon meeting the trigger condition but will not expand
                        # if using $true, the script will expand the configured volume upon meeting the trigger condition
$ExpandThresholdGB      = 100 # Amount of available space on the volume in GB that triggers volume auto-expansion
$ExpandThresholdPercent = 10  # Percentage of available space on the volume in GB that triggers volume auto-expansion
                        # One of the above 2 parameters is required. If both are provided, the script will use the larger one
$ExpandAmountGB         = 2  # Value of 200 will expand the volume by 200 GB
$ExpandAmountPercent    = 1   # Value of 10 will expand the volume by 10% - e.g. from 1 TB to 1.1 TB
                        # One of the above 2 parameters is required. If both are provided, the script will use the larger one
$NotToExceedGB          = 1024 # Volume size not to be exceeded by this script
$DiskNumber             = 6 # Lookup the iSCSI volume disk number for this volume on your file server Disk Management
$DriveLetter            = 'J' # Lookup the iSCSI volume drive letter on your file server Disk Management
$LogFile                = "\\$env:COMPUTERNAME\d$\Sandbox\logs\AutoExpand-StorSimpleVolume-$(Get-Date -format yyyy-MM-dd_HH-mm-sstt).txt"
$EmailSender            = 'StorSimple Volume Size Monitor <DoNotReply@YourDomain.com>'
$EmailRecipients        = @( # Add one or more recipients email addresses below, each on a line:
                            'Sam Boutros <sboutros@vertitechit.com>'
                            'Your Name <YourName@YourDomain.com>'
                          )
$SMTPServer             = 'smtp.YourDomain.com' 
#endregion


function Log {
<# 
 .Synopsis
  Function to log input string to file and display it to screen

 .Description
  Function to log input string to file and display it to screen. Log entries in the log file are time stamped. Function allows for displaying text to screen in different colors.

 .Parameter String
  The string to be displayed to the screen and saved to the log file

 .Parameter Color
  The color in which to display the input string on the screen
  Default is White
  Valid options are
    Black
    Blue
    Cyan
    DarkBlue
    DarkCyan
    DarkGray
    DarkGreen
    DarkMagenta
    DarkRed
    DarkYellow
    Gray
    Green
    Magenta
    Red
    White
    Yellow

 .Parameter LogFile
  Path to the file where the input string should be saved.
  Example: c:\log.txt
  If absent, the input string will be displayed to the screen only and not saved to log file

 .Example
  Log -String "Hello World" -Color Yellow -LogFile c:\log.txt
  This example displays the "Hello World" string to the console in yellow, and adds it as a new line to the file c:\log.txt
  If c:\log.txt does not exist it will be created.
  Log entries in the log file are time stamped. Sample output:
    2014.08.06 06:52:17 AM: Hello World

 .Example
  Log "$((Get-Location).Path)" Cyan
  This example displays current path in Cyan, and does not log the displayed text to log file.

 .Example 
  "$((Get-Process | select -First 1).name) process ID is $((Get-Process | select -First 1).id)" | log -color DarkYellow
  Sample output of this example:
    "MDM process ID is 4492" in dark yellow

 .Example
  log "Found",(Get-ChildItem -Path .\ -File).Count,"files in folder",(Get-Item .\).FullName Green,Yellow,Green,Cyan .\mylog.txt
  Sample output will look like:
    Found 520 files in folder D:\Sandbox - and will have the listed foreground colors

 .Link
  https://superwidgets.wordpress.com/category/powershell/

 .Notes
  Function by Sam Boutros
  v1.0 - 08/06/2014
  v1.1 - 12/01/2014 - added multi-color display in the same line

#>

    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')] 
    Param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeLine=$true,
                   ValueFromPipeLineByPropertyName=$true,
                   Position=0)]
            [String[]]$String, 
        [Parameter(Mandatory=$false,
                   Position=1)]
            [ValidateSet("Black","Blue","Cyan","DarkBlue","DarkCyan","DarkGray","DarkGreen","DarkMagenta","DarkRed","DarkYellow","Gray","Green","Magenta","Red","White","Yellow")]
            [String[]]$Color = "Green", 
        [Parameter(Mandatory=$false,
                   Position=2)]
            [String]$LogFile,
        [Parameter(Mandatory=$false,
                   Position=3)]
            [Switch]$NoNewLine
    )

    if ($String.Count -gt 1) {
        $i=0
        foreach ($item in $String) {
            if ($Color[$i]) { $col = $Color[$i] } else { $col = "White" }
            Write-Host "$item " -ForegroundColor $col -NoNewline
            $i++
        }
        if (-not ($NoNewLine)) { Write-Host " " }
    } else { 
        if ($NoNewLine) { Write-Host $String -ForegroundColor $Color[0] -NoNewline }
            else { Write-Host $String -ForegroundColor $Color[0] }
    }

    if ($LogFile.Length -gt 2) {
        "$(Get-Date -format "yyyy.MM.dd hh:mm:ss tt"): $($String -join " ")" | Out-File -Filepath $Logfile -Append 
    } else {
        Write-Verbose "Log: Missing -LogFile parameter. Will not save input string to log file.."
    }
}


#region Initialize
<#
See this post for more details on connecting to StorSimple via Powershell:
https://superwidgets.wordpress.com/2014/06/26/using-azure-storage-with-powershell-getting-started/
To get Publish Settings File if needed - first time only
Clear-AzureProfile -Force -Verbose
Get-AzurePublishSettingsFile 
Import-AzurePublishSettingsFile '.\Your File Name Here-3-30-2016-credentials.publishsettings'
#>

#region Connect to StorSimple Manager
try {
    Select-AzureSubscription -SubscriptionName "$SubscriptionName" -Current
} catch {
    log 'Failed to connect to Azure subscription',$SubscriptionName Magenta,Yellow $LogFile
    break
}
try {
    $Result = Select-AzureStorSimpleResource -ResourceName $StorSimpleManagerName -RegistrationKey $RegistrationKey
#    log ($Result | Out-String) Green $LogFile
} catch {
    log 'Failed to connect to StorSimple Manager Service',$StorSimpleManagerName,'Check values entered for of StorSimpleManagerName and RegistrationKey' Magenta,Yellow,Magenta $LogFile
    break
}

if (-not (Test-Path (Split-Path -Path $LogFile))) {
    New-Item -Path (Split-Path -Path $LogFile) -ItemType Directory -Force -Confirm:$false | Out-Null
}
#endregion

#region Get Volume Size:
try { 
    $SSVolumeSizeGB = (Get-AzureStorSimpleDeviceVolume -DeviceName $SSDeviceName -VolumeName $SSVolumeName).SizeInBytes/1GB
    $VolFreeSpaceGB = (Get-Volume -DriveLetter $DriveLetter).SizeRemaining/1GB
    log 'Volume',$SSVolumeName,'current size is',$SSVolumeSizeGB,'GB -',("{0:N0}" -f ($VolFreeSpaceGB)),'GB free' Green,Cyan,Green,Cyan,Green,Cyan,Green $LogFile
} catch {
    log 'Failed to get volume',$SSVolumeName,'information, check the device name and volume name spelling..' Magenta,Yellow,Magenta $LogFile
    break
}
#endregion

#region Validate ExpandThresholdGB
if ($ExpandThresholdGB) {
    if ($ExpandThresholdPercent) { # Both provided
        log 'Both ExpandThresholdGB',$ExpandThresholdGB,'GB and ExpandThresholdPercent',$ExpandThresholdPercent,'% provided,' Green,Cyan,Green,Cyan,Green $LogFile -NoNewLine
        if ($ExpandThresholdGB -lt ($SSVolumeSizeGB*$ExpandThresholdPercent/100)) {
            $ExpandThresholdGB = $SSVolumeSizeGB*$ExpandThresholdPercent/100
        }
        log 'using the larger value',$ExpandThresholdGB,'GB' Green,Cyan,Green $LogFile
    } else { # GB only provided
        log 'Using the provided value for ExpandThresholdGB',$ExpandThresholdGB,'GB' Green,Cyan,Green $LogFile
    }
} else {
    if ($ExpandThresholdPercent) { # % only provided
        $ExpandThresholdGB = $SSVolumeSizeGB*$ExpandThresholdPercent/100
        log 'Using the provided value for ExpandThresholdPercent',$ExpandThresholdPercent,'% of Volume Size',$SSVolumeSizeGB,'=',$ExpandThresholdGB,'GB' Green,Cyan,Green,Cyan,Green,Cyan,Green $LogFile
    } else { # neither provided
        log 'Error: neither ExpandThresholdGB or ExpandThresholdPercent provided. One of these 2 must be provided' Magenta $LogFile
        break
    }
}
#endregion

#region Validate ExpandAmountGB
if ($ExpandAmountGB) {
    if ($ExpandAmountPercent) { # Both provided
        log 'Both ExpandAmountGB',$ExpandAmountGB,'GB and ExpandAmountPercent',$ExpandAmountPercent,'% provided,' Green,Cyan,Green,Cyan,Green $LogFile -NoNewLine
        if ($ExpandAmountGB -lt ($SSVolumeSizeGB*$ExpandAmountPercent/100)) {
            $ExpandAmountGB = $SSVolumeSizeGB*$ExpandAmountPercent/100
        }
        log 'using the larger value',$ExpandAmountGB,'GB' Green,Cyan,Green $LogFile
    } else { # GB only provided
        log 'Using the provided value for ExpandAmountGB',$ExpandAmountGB,'GB' Green,Cyan,Green $LogFile
    }
} else {
    if ($ExpandAmountPercent) { # % only provided
        $ExpandAmountGB = $SSVolumeSizeGB*$ExpandAmountPercent/100
        log 'Using the provided value for ExpandAmountPercent',$ExpandAmountPercent,'% of Volume Size',$SSVolumeSizeGB,'=',$ExpandAmountGB,'GB' Green,Cyan,Green,Cyan,Green,Cyan,Green $LogFile
    } else { # neither provided
        log 'Error: neither ExpandAmountGB or ExpandAmountPercent provided. One of these 2 must be provided' Magenta $LogFile
        break
    }
}
#endregion

#region Validate NotToExceedGB
if ($NotToExceedGB -lt 1 -or $NotToExceedGB -gt 64000){
    log 'Error: NotToExceed value',$NotToExceedGB,'must be between 1 and 64,000 (GB)' Magenta,Yellow,Magenta $LogFile
    break
}
if ($NotToExceedGB -le $SSVolumeSizeGB){
    log 'Error: volume',$SSVolumeName,'current size',$SSVolumeSizeGB,'is already at/above NotToEXceed value',$NotToExceedGB Magenta,Yellow,Magenta,Yellow,Magenta,Yellow $LogFile
    break
}
$ExceedMsg = ''
if ($SSVolumeSizeGB+$ExpandAmountGB -gt $NotToExceedGB) {
    $OriginalExpandAmountGB = $ExpandAmountGB
    $ExpandAmountGB = $NotToExceedGB - $SSVolumeSizeGB
    log 'Requested ExpandAmountGB',$OriginalExpandAmountGB,'puts new volume size',($SSVolumeSizeGB+$OriginalExpandAmountGB),'above the NotExceed value',$NotToExceedGB Magenta,Yellow,Magenta,Yellow,Magenta,Yellow $LogFile
    log 'Expanding volume',$SSVolumeName,'current size',$SSVolumeSizeGB,'by',$ExpandAmountGB,'only to meet NotExceed value',$NotToExceedGB Green,Cyan,Green,Cyan,Green,Cyan,Green,Cyan $LogFile
    $ExceedMsg = "Requested ExpandAmountGB $OriginalExpandAmountGB puts new volume size $($SSVolumeSizeGB+$OriginalExpandAmountGB) above the NotExceed value $NotToExceedGB"
    $ExceedMsg += "Expanding volume $SSVolumeName current size $SSVolumeSizeGB by $ExpandAmountGB only to meet NotExceed value $NotToExceedGB"
}
log 'Validated volume',$SSVolumeName,'size',$SSVolumeSizeGB,'can be expanded to',($SSVolumeSizeGB+$ExpandAmountGB),'without crossing NotToExceed amount of',$NotToExceedGB Green,Cyan,Green,Cyan,Green,Cyan,Green,Cyan $LogFile
$ExceedMsg += "Validated volume $SSVolumeName size $SSVolumeSizeGB can be expanded to $($SSVolumeSizeGB+$ExpandAmountGB) without crossing NotToExceed amount of $NotToExceedGB"
#endregion

#region Trigger
if ($VolFreeSpaceGB -le $ExpandThresholdGB) { 
    $Trigger = $true 
    log 'Volume',$SSVolumeName,'has',("{0:N0}"-f $VolFreeSpaceGB),'GB free, which is at/below the ExpandThresholdGB value',$ExpandThresholdGB Green,Cyan,Green,Cyan,Green,Cyan $LogFile
    log 'Volume expansion condition met, triggering volume expansion..' Green $LogFile
} else { 
    $Trigger = $false 
    log 'Volume',$SSVolumeName,'has',("{0:N0}"-f $VolFreeSpaceGB),'GB free, which is above the ExpandThresholdGB value',$ExpandThresholdGB Green,Cyan,Green,Cyan,Green,Cyan $LogFile
    log 'Volume expansion condition NOT met, not expanding volume..' Yellow $LogFile
}
#endregion

#endregion


#region Expand volume
if ($Trigger) {
    if ($Expand) {
        # First expand volume in Azure
        log 'Expanding volume',$SSVolumeName,'from',$SSVolumeSizeGB,'GB to',($SSVolumeSizeGB+$ExpandAmountGB),'GB in Azure..' Green,Cyan,Green,Cyan,Green,Cyan,Green $LogFile -NoNewLine
        try {
            $Result = Set-AzureStorSimpleDeviceVolume -DeviceName $SSDeviceName -VolumeName $SSVolumeName -VolumeSizeInBytes (($SSVolumeSizeGB+$ExpandAmountGB)*1GB) -WaitForComplete
            log 'succeeded ' Yellow $LogFile -NoNewLine
            if ((Get-AzureStorSimpleDeviceVolume -DeviceName $SSDeviceName -VolumeName $SSVolumeName).SizeInBytes/1GB -eq $SSVolumeSizeGB+$ExpandAmountGB) {
                log 'and verified' Green $LogFile
                $ExpandMsg = "Expanding volume $SSVolumeName from $SSVolumeSizeGB GB to $($SSVolumeSizeGB+$ExpandAmountGB) GB in Azure... succeeded and verified<br>"
    #            log ($Result | Out-String) Green $LogFile
            } else {
                log 'New volume size verification failed.' Magenta $LogFile
    #            log ($Result | Out-String) Green $LogFile
                break
            }
        } catch {
            log 'Failed.' Magenta $LogFile
            break
        }

        # Next expand partition on SMB file server 
        try {
            Update-HostStorageCache 
            $DiskSizeGB  = (Get-Disk -Number $DiskNumber).Size/1GB
            $AllocatedGB = (Get-Disk -Number $DiskNumber).AllocatedSize/1GB 
            if ($DiskSizeGB -gt $AllocatedGB) {
                $PartitionNumber = (Get-Partition -DiskNumber $DiskNumber | where { $_.DriveLetter -eq $Driveletter }).PartitionNumber
                $MaxSize = (Get-PartitionSupportedSize –DiskNumber $DiskNumber –PartitionNumber $PartitionNumber).SizeMax
                log 'Expanding partition #',$PartitionNumber,'on disk #',$DiskNumber,'to',("{0:N0}" -f ($MaxSize/1GB)),'GB..' Green,Cyan,Green,Cyan,Green,Cyan,Green $LogFile -NoNewLine
                Resize-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -Size $MaxSize
                # Verify success:
                $AllocatedGB = (Get-Disk -Number $DiskNumber).AllocatedSize/1GB
                if ($DiskSizeGB -eq $AllocatedGB) { 
                    log ' succeeded' Green $LogFile 
                    $ExpandMsg += "Expanding partition # $PartitionNumber on disk # $DiskNumber to $("{0:N0}" -f ($MaxSize/1GB)) GB... succeeded"
                } else { 
                    log ' failed' Magenta $LogFile 
                    $ExpandMsg += "Expanding partition # $PartitionNumber on disk # $DiskNumber to $("{0:N0}" -f ($MaxSize/1GB)) GB.. FAILED"
                }
            } else {
                log 'Disk #',$DiskNumber,'size',$DiskSizeGB,'GB is fully allocated - cannot be expanded' Magenta,Yellow,Magenta,Yellow,Magenta $LogFile
                $ExpandMsg += "Disk # $DiskNumber size $DiskSizeGB GB is fully allocated - cannot be expanded"
            }
        } catch {
            log 'Failed' Magenta $LogFile
        }
    } else {
        log 'Parameter $Expand is set to $false, not expanding volume',$SSVolumeName Green,Cyan $LogFile
        $ExpandMsg = "Parameter 'Expand' is set to 'false', not expanding volume $SSVolumeName"
    } # Expand
} #Trigger

#endregion  


#region Notify
if ($Notify -and $Trigger) {
    $Error.Clear()
    try {
        log 'Sending email notification..' Green $LogFile -NoNewLine
        $Subject = "StorSimple Volume AutoExpander report generated on $(Get-Date -f 'dd/MM/yyyy HH:mm')"
        $Body = "<center><h2>$Subject</h2></center>"
        $Body += "<table width=100% cellpadding=2 cellspacing=0 border=1>"
        $Body += "<tr><td align=right>Server Name</td><td>$env:COMPUTERNAME</td></tr>"
        $Body += "<tr><td align=right bgcolor=#C3C3C3>Volume Name</td><td bgcolor=#C3C3C3>$SSVolumeName</td></tr>"
        $Body += "<tr><td align=right>Original Size</td><td>$SSVolumeSizeGB GB</td></tr>"
        $Body += "<tr><td align=right bgcolor=#C3C3C3>Script input: ExpandThresholdGB (volume free space in GB to trigger auto-expansion)</td><td bgcolor=#C3C3C3>$ExpandThresholdGB GB</td></tr>"
        $Body += "<tr><td align=right>Volume free space</td><td>$("{0:N0}" -f $VolFreeSpaceGB)</td></tr>"
        $Body += "<tr><td colspan=2 bgcolor=#C3C3C3>$ExceedMsg</td></tr>"
        if ($Trigger) {
            $Body += "<tr><td colspan=2>Volume $SSVolumeName has $("{0:N0}"-f $VolFreeSpaceGB) GB free, which is at/below the ExpandThresholdGB value $ExpandThresholdGB<br>"
            $Body += "Volume expansion condition met, triggering volume expansion.. </td></tr>"
        } else {
            $Body += "<tr><td colspan=2>Volume $SSVolumeName has $("{0:N0}"-f $VolFreeSpaceGB) GB free, which is above the ExpandThresholdGB value $ExpandThresholdGB<br>"
            $Body += "Volume expansion condition NOT met, not expanding volume.</td></tr>"
        }
        $Body += "<tr><td colspan=2 bgcolor=#C3C3C3>$ExpandMsg</td></tr></table>"
        Send-MailMessage -From $EmailSender -To $EmailRecipients -Body $Body -SmtpServer $SMTPServer -Subject $Subject -Priority High -BodyAsHtml -ErrorAction Stop
        log 'succeeded' Green $LogFile
    } catch {
        log 'Failed to send email report' Magenta $LogFile
        log "Details: $Error" Magenta $LogFile
    }
} else {
    log 'Parameter $Notify is set to $false OR expansion condition not met, not sending email notification..' Green,Cyan $LogFile
}
#endregion