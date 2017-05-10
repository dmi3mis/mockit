# import-prepare-v0.3.ps1     #
# Copyleft 2014               #
# A MOC Deploy Solution       #
# Created by Dmitry Mischenko #
# dmitrymi@softline.ru        #

Param
(
    [Parameter(Mandatory=$true,Position=0)]
    [String]$MOCN="",

    [Parameter(Mandatory=$false,Position=1)]
    [String]$SourcePath="\\dpc3\d\Microsoft Learning",
	#[String]$SourcePath="d:\Microsoft Learning",
        
    [Parameter(Mandatory=$false)]
    [switch]$NocopyVM=$false,
    
    [Parameter(Mandatory=$false)]
    [switch]$NocopyBASE=$false,

    [Parameter(Mandatory=$false)]
    [switch]$Norepack=$false,    
    
    [Parameter(Mandatory=$false)]
    [switch]$NoRearm=$false,

    [Parameter(Mandatory=$false)]
    [switch]$Preparehost=$false,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoStartingImage=$false,

    [Parameter(Mandatory=$false)]
    [String]$HV_hostname= "HOST1",

    [Parameter(Mandatory=$false)]
    [String]$DefaultPassword="Pa`$`$w0rd",    

    [Parameter(Mandatory=$null)]
    [String]$AutoRebootTo=$null,
    
    [Parameter(Mandatory=$false)]
    [switch]$vhddeleteafterrepack=$false

)


$host.UI.RawUI.BackgroundColor = "Black"; Clear-Host
# Elevate
Write-Host "Checking for elevation... " -NoNewline
$CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
if (($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) -eq $false)  {
    $ArgumentList = "-noprofile -noexit -file `"{0}`" -Path `"$Path`""
    If ($DeploymentOnly) {$ArgumentList = $ArgumentList + " -DeploymentOnly"}
    Write-Host "elevating"
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($ArgumentList -f ($myinvocation.MyCommand.Definition))
    Exit
}

$Host.UI.RawUI.BackgroundColor = "Black"; Clear-Host
$StartTime = Get-Date
$Validate = $true

Write-Host ""
Write-Host "Start time:" (Get-Date)




##
## Jason Kline
## CopyFiles-Bits.ps1
## 01/19/2015
##

function CopyFiles-Bits
{
# Set Parameters
Param (
[Parameter(Mandatory=$true)]
[String]$Source,
[Parameter(Mandatory=$true)]
[String]$Destination
)

# Read all directories located in the sorce directory
$dirs = Get-ChildItem -Name -Path $Source -Directory -Recurse
$files = Get-ChildItem -Name -Path $Source -File
# Start Bits Transfer for all items in each directory. Create Each directory if they do not exist at destination.

$exists = Test-Path $Destination
if ($exists -eq $false) {New-Item $Destination -ItemType Directory}

foreach ($f in $files)
    {
    $srcname = $source + "\" + $f.PSChildName
    $dstname = $Destination + "\" + $f.PSChildName
    Start-BitsTransfer -Source $srcname -Destination $Destination -Description "to $dstname" -DisplayName "Copying $srcname"
    }

foreach ($d in $dirs)
    {
    $srcsubdir = $Source +"\" + $d
    $dstsubdir = $Destination + "\" + $d
    
    $exists = Test-Path $dstsubdir
    if ($exists -eq $false) {New-Item $dstsubdir -ItemType Directory}
    
    $files = Get-ChildItem -Name -Path $srcsubdir -File
    foreach ($f in $files)
        {
        $srcfilename = $srcsubdir + "\" + $f.PSChildName
        $dstfilename = $dstsubdir + "\" + $f.PSChildName
        Start-BitsTransfer -Source $srcfilename -Destination $dstsubdir -Description "to $dstfilename" -DisplayName "Copying $srcfilename"
        }
   
    }

}

function convert-vhd-my ([string]$vhdpath) 
{
        $vhdxpath =$vhdpath+"x"
        If (Test-Path $vhdxpath)
            { 
                # "We will delete existing vhdx on path $vhdxpath"
                Remove-Item $vhdxpath
            }

        $vhd= Mount-VHD -Path $vhdpath -Passthru -NoDriveLetter -ReadOnly
        
        $vhdx=New-VHD -Path $vhdxpath -Dynamic -SourceDisk $vhd.Number
        Dismount-VHD $vhdpath
        #vhdx with 4k may have some good performance effect on AF disks
		#have compability problem with Exchange 2010 DAG. 
        Set-VHD -Path $vhdx.Path -PhysicalSectorSizeBytes 4096
        [string]$vhdx.Path
}

function get-bcdeditidofdescr ([string]$description) 
{
    Invoke-Expression "chcp 437 >null"
    $output = invoke-expression "bcdedit /v"
    $test=$output|Select-String "description             $description" -context 3,0
    foreach ( $i in $test ) {$i.Context.PreContext[0].Trimstart("identifier              ")};
}

function prepare-vol ($vl,$filename,$content)
{
    $DL = $vl.DriveLetter + "`:"
	New-item -type file "$DL\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\$filename"  -Force -Value $content
	reg load HKLM\TempHive $DL\Windows\System32\config\SOFTWARE
	$regkey = "HKLM:\TempHive\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
	$useranddomain= get-itemproperty -path $regkey -name LastLoggedOnSAMUser
	$user = ($useranddomain.LastLoggedOnSAMUser).split("\").item(1)
	$domain = ($useranddomain.LastLoggedOnSAMUser).split("\").item(0)
	$regkey = "HKLM:\TempHive\Microsoft\Windows NT\CurrentVersion\Winlogon"
	set-itemproperty -path $regkey -name AutoAdminLogon -value 1
	set-itemproperty -path $regkey -name DefaultUserName -value $user
	set-itemproperty -path $regkey -name DefaultPassword -value $Defaultpassword
	set-itemproperty -path $regkey -name DefaultDomainName -value $domain
	$regkey = "HKLM:\TempHive\Microsoft\Windows\CurrentVersion\RunOnce" 
	set-itemproperty -Path $regkey  -name $filename -value "c:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\$filename"
	[gc]::collect()
	reg unload HKLM\TempHive
	#Lets try add autologon bat file for administrator user account
	$ntuserpaths=Get-ChildItem "$DL\Users\Administrator*\NTUSER.DAT" -Force -Recurse -ErrorAction SilentlyContinue
	foreach ($ntuser in $ntuserpaths.Fullname)
		{
				Write-Host "reg load HKLM\TempHive $ntuser"
				reg load HKLM\TempHive "$ntuser"
				$regkey = "HKLM:\TempHive\Software\Microsoft\Windows\CurrentVersion\Policies\System"
				#some vms disable registry editing tools so try to enable it.
                set-itemproperty -Path $regkey -name DisableRegistryTools -value 0
				[gc]::collect()
				reg unload HKLM\TempHive
				}

}
function Autorun-bat-at-hostnextboot ($filename,$content)
{
	New-item -type file "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\$filename"  -Force -Value $content
	$regkey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"
	$useranddomain= get-itemproperty -path $regkey -name LastLoggedOnSAMUser
	$user = ($useranddomain.LastLoggedOnSAMUser).split("\").item(1)
	$domain = ($useranddomain.LastLoggedOnSAMUser).split("\").item(0)
	$regkey = "HKLM:\TempHive\Microsoft\Windows NT\CurrentVersion\Winlogon"
	set-itemproperty -path $regkey -name AutoAdminLogon -value 1
	set-itemproperty -path $regkey -name DefaultUserName -value $user
	set-itemproperty -path $regkey -name DefaultPassword -value $Defaultpassword
	set-itemproperty -path $regkey -name DefaultDomainName -value $domain
	$regkey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" 
	set-itemproperty -Path $regkey  -name $filename -value "c:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\$filename"
	#Lets try add autologon bat file for administrator user account
	$ntuserpaths=Get-ChildItem "$DL\Users\Administrator*\NTUSER.DAT" -Force -Recurse -ErrorAction SilentlyContinue
	foreach ($ntuser in $ntuserpaths.Fullname)
		{
				Write-Host "reg load HKLM\TempHive $ntuser"
				reg load HKLM\TempHive "$ntuser"
				$regkey = "HKLM:\TempHive\Software\Microsoft\Windows\CurrentVersion\Policies\System"
				#some vms di/sable registry editing tools so try to enable it.
                set-itemproperty -Path $regkey -name DisableRegistryTools -value 0
				[gc]::collect()
				reg unload HKLM\TempHive
				}

}

function prepare-hostvhd ($vhd)
{

 $vhd_mounted = Mount-VHD -Path $vhd.Fullname -Passthru
 Start-Sleep -Seconds 3
 $disk = Get-Disk $vhd_mounted.Number
 $part = $disk| Get-Partition
 if(!($part)) {Dismount-VHD -Path $vhd.FullName; throw "No partitions in vhdx file!"};

 $vol = $part |Get-Volume 

# If Some Volume Exists and have Windows Folder, so lets inject drivers and install components
foreach ($vl in $vol) 
{  
 $DL = $vl.DriveLetter + "`:"
 New-PSDrive -Name $vl.DriveLetter  -PSProvider FileSystem -Root $DL

 if(Test-Path -PathType Container -Path "$DL\Windows")
 {
    
    New-item -Type file "$DL\prephost.ps1"  -Force -Value $prephost
    prepare-vol $vl startps.cmd $startps
    prepare-vol $vl rearm.cmd $rearm

    $output = Invoke-Expression "dism /?"

    $dismversion=$output |Select-String -Pattern 'Version'

    if($dismversion.Line -eq "Version: 6.3.9600.17031") 
    {
        Add-WindowsDriver –Path $DL `
                       –Driver $DriversDir `
                       –Recurse `
                       -ForceUnsigned `
                       -Verbose
        Install-WindowsFeature -Vhd $DL -IncludeManagementTools -Name Hyper-V
        Install-WindowsFeature -Vhd $DL -IncludeManagementTools -Name NET-Framework-Core
        Install-WindowsFeature -Vhd $DL -IncludeManagementTools -Name Desktop-Experience

    }
    else
    {
    
        # Since we are in Server 2012 RTM Host 
        # native dism Version: 6.2.9200.16384 cannot fully functional work with Server 2012 R2 offline image.
        # We will use dism Version: 6.3.9600.16384 from Windows 8.1 ADK stated with $DismPath verb.
        # later we will do it much simpler
        # Add-WindowsDriver –Path $DL `
        #                   –Driver $DriversDir `
        #                   –Recurse `
        #                   -ForceUnsigned `
        #                   -Verbose
    pushd $DismPath
    .\dism.exe /image:$DL /add-driver /driver:$DriversDir  /recurse /forceunsigned
    

    
    #enable Hyper-V and some other features.
    .\dism.exe /image:$DL /enable-feature /all /featurename:Microsoft-Hyper-V `
                                               /featurename:VmHostAgent `
                                               /featurename:Microsoft-Hyper-V-Management-Clients `
                                               /featurename:RSAT-Hyper-V-Tools-Feature `
                                               /featurename:Microsoft-Hyper-V-Management-PowerShell `
                                               /featurename:RasRoutingProtocols `
                                               /featurename:DesktopExperience
    popd
    }
  
  }
 Remove-PSDrive $vl.DriveLetter
}
  
 
Dismount-VHD -Path $vhd.Fullname  
}
 

# $SOURCE_PATH is file share with files of MOC materials.
# File share must contain unpacked course vm files from MOC Download Centre
# It must looks like
# \\fileshare\share\
#                  |- 1234A\             - we will name it $MOCN
#                  |       |- Drives\
#                  |-Base\
#                  |     |-Base???-W*.vhd
#                  |     |-Base10A-WS08R2-HV.vhd
#                  |     |-Drives\
#                  |     |       |-WS*.vhd
#                  |     |       |-WS08R2-NYC-DC1.vhd

$MSDir= "C:\Program Files\Microsoft Learning"
$DriversDir="$SourcePath\Drivers"
$DismPath="$SourcePath\scripts\DISM"
$MOC=$MOCN.Substring(0,$MOCN.Length-1)


$shutdown = '
rem plan to shutdown the system in 10 secs.
shutdown /s /c "system is prepared" /f /t 10
rem killing myself
del /f /q %0
'

$rearm = '
rem rearming windows
@cscript //nologo %windir%\System32\slmgr.vbs /rearm

rem Lets try to rearm office 2013 if present
"%ProgramFiles(x86)%\Microsoft Office\Office15\ospprearm.exe"

rem revert back start of server manager at logon
reg add "HKLM\Software\Microsoft\ServerManager" /v DoNotOpenServerManagerAtLogon /t REG_DWORD /f /d 0
	
rem Enable host to remote administration 
reg add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /f /d 0
rem Everyone can use remote desktop
net localgroup "remote desktop users" everyone /add

netsh advfirewall firewall set rule group="@FirewallAPI.dll,-28752" new enable=Yes
	
rem remove autoadminlogon
reg add    "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon  /t REG_SZ /f /d 0
reg delete "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f
reg delete "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
reg delete "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /f

rem killing myself
del /f /q %0
'


if(!($NocopyVM))
{

if (!(Test-Path $SourcePath)) {throw Sourcepath $SourcePath seems do not exists or cannot connect.}
Write-Host "lets copy all VM files that we need"
#mkdir "$MSDir\$MOC\Drives"
CopyFiles-Bits -Source "$SourcePath\$MOCN\Drives" -Destination "$MSDir\$MOC\Drives"
}

if(!($NocopyBASE))
{


# Check if hard links of Base files has already prepared with script Make-BaseHardlinks.bat
# If subdir Base exist then copy from if else we will parse txt's.
 
if (test-path "$SourcePath\$MOCN\Base")
	{
	CopyFiles-Bits -Source "$SourcePath\$MOCN\Base" -Destination "$MSDir\Base"  
	}
else
	{
	$TXTs = Get-ChildItem "$MSdir\$MOC\Drives" | ? {$_.FullName -like "*.txt"}

	 
		{
		#convert txt name to vhd name. Name of txt is like Base11A-WS08R2SP1.txt
		#We will change *.txt to *.vhd in name.
		$FirstDefis = $TxtFile.Name.IndexOf('-')
  		$Dot = $TxtFile.Name.IndexOf('.')
  		#$VHDName = $TxtFile.Name.Substring($FirstDefis+1,$Dot - $FirstDefis-1)+".vhd"
		$VHDName = $TxtFile.Name.Substring(0,$Dot)+".vhd"
  		If ($VHDName -like "Base*")
  			{
			CopyFiles-Bits -Source "$SourcePath\Base\$VHDName" -Destination "$MSdir\Base"
  			}
  		else
  			{
			CopyFiles-Bits -Source "$SourcePath\Base\Drives\$VHDName" -Destination "$MSdir\Base\Drives"
  			}
		}
  
	}
}

if (!($Preparehost))
{

# Lets create VM networks for $MOC 

# Install Hyper-V Tools and Hyper-V PowerShell Module if not already installed. 
# If it is already installed it will just return a prompt saying no change needed and continue
# Install-WindowsFeature Hyper-V-Tools,Hyper-V-PowerShell

# See if a Private Switch named "Private Network" already exists and assign True or False value to the Variable to track if it does or not
$PrivateNetworkVirtualSwitchExists = ((Get-VMSwitch | where {$_.name -eq "Private Network" }).count -ne 0)

# If statement to check if Private Switch already exists. If it does write a message to the host 
# saying so and if not create Private Virtual Switch
if ($PrivateNetworkVirtualSwitchExists -eq "True")
    {
    Write-Host "< Private Network >   ---- switch already Exists. Will not create."
    } 
else
    {
    Write-Host "< Private Network >   ---- switch do not exist. We will create:"  
    $vmswitch= New-VMSwitch -SwitchName "Private Network" -SwitchType Private
    $vmname = "vEthernet " + "(" +$vmswitch.Name + ")"
    $netadapter = Get-NetAdapter -Name $vmname
    $netadapter | Set-NetIPInterface -Dhcp Disabled
    $netadapter | New-NetIPAddress -IPAddress 172.16.0.1 -PrefixLength 16 #–DefaultGateway 172.16.0.1
    }

if (! (Get-VMSwitch "Private Network 2")) 
 {
  $vmswitch = new-VMSwitch "Private Network 2" -SwitchType Private -ErrorAction SilentlyContinue
  $vmname = "vEthernet " + "(" +$vmswitch.Name + ")"
 }

 
 # for 20411D-INET1
 if (! (Get-VMSwitch "Internet")) 
 {
  $vmswitch = new-VMSwitch "Internet" -SwitchType Private -ErrorAction SilentlyContinue
  $vmname = "vEthernet " + "(" +$vmswitch.Name + ")"
 }

Write-Host Lets Start all `*.bat files in $MSDir\$MOC
get-childitem -path "$MSdir\$MOC" -recurse -filter "*.bat" | foreach-object {
  Write-Host Starting Bat Files in $_.FullName
  start-process $ENV:SystemRoot\system32\cmd.exe -argumentlist ('/c "' + $_.FullName + '"'+ ' <nul >nul 2>&1') -WindowStyle Hidden
}

Write-Host Lets import all VMs  in $MSDir\$MOC
$VMpathxml = Get-ChildItem "C:\Program Files\Microsoft Learning\$MOC\*.exp" -recurse
{
  
	Write-Host importing $pathxml
        Import-VM -Path $pathxml -ErrorAction SilentlyContinue -Register

}

$VMpathxml = Get-ChildItem "C:\Program Files\Microsoft Learning\$MOC\*.xml" -recurse
foreach ($pathxml in $VMpathxml.Fullname)
{
  
	Write-Host importing $pathxml
        Import-VM -Path $pathxml -ErrorAction SilentlyContinue -Register

}

$vms = Get-VM "$MOCN*"

# Repack vhd files to vhdx and reconnect it to VM in not disabled by switch $repacktovhdx
if(!($Norepack))
{   
    foreach ($vm in $vms)
    {
    Write-host We will work with $vm.Name
    
    Write-host Before
    $vhd= Get-VMHardDiskDrive $vm | ? {$_.path -ilike "*vhd"}	
    $vhd |ft  Path,VhdFormat,VhdType,FileSize,Size,LogicalSect,PhysicalSec -AutoSize
    foreach ($v in $vhd )
     {
        
        $vhdxpath =convert-vhd-my $v.Path
       
        # "we will Re-Attach new vhdx to vm"
        Set-VMHardDiskDrive -VMName $v.VMName `
                            -Path $vhdxpath `
                            -ControllerType $v.ControllerType `
                            -ControllerNumber $v.ControllerNumber `
                            -Controllerlocation  $v.ControllerLocation
        if($vhddeleteafterrepack)
            { Get-Item $v.Path |Remove-Item }
        
        
     }
    
    Write-host After
    $vhdx= Get-VMHardDiskDrive $vm
    $vhdx |ft  Path,VhdFormat,VhdType,FileSize,Size,LogicalSect,PhysicalSec -AutoSize
    }

}



$vms = Get-VM "$MOCN*"


if(!($NoRearm))
{


#Prepare each VM with autologon $rearm.bat file
foreach ($VM in $vms)  
	{
	 # Check for vhd's based of name.
     Write-host We will prepare $vm.Name
	 $vmvhd=$vm.HardDrives
	 foreach ($vhd in $vmvhd)
	 {
        $vh= Mount-VHD -Path $vhd.Path -Passthru 
        Start-Sleep -Seconds 3
        $disk = Get-Disk $vh.Number
        $part = $disk| Get-Partition
        # no partitions exist, so nothing to do
        if(!($part)) {Dismount-VHD -Path $vhd.Path; continue};


        $vol =  $part| Get-Volume                      # |?{$DL=$_.DriveLetter; New-PSDrive -Name $DL -PSProvider FileSystem -Root "$DL`:" ;Test-Path -PathType Container -Path "$DL`:\Windows" }
		

        foreach ($vl in $vol) 
		{
         $DL=$vl.DriveLetter
         New-PSDrive -Name $DL -PSProvider FileSystem -Root "$DL`:"
		 if(Test-Path -PathType Container -Path "$DL`:\Windows")
         {
          prepare-vol $vl rearm.cmd $rearm
          prepare-vol $vl shutdown.cmd $shutdown

         }
         Remove-PSDrive $DL
		}
        Dismount-VHD -Path $vhd.Path
     }

     Start-VM $VM
     Write-Host we will wait until $VM.Name is started, apply rearm and then shutdown.
     do {Start-Sleep -milliseconds 300} 
      until ($VM.state -eq "Off")
     }
}


# Lets create StartingImage snapshot on all $VM
if(!($NoStartingImage)) { foreach ($VM in $vms) { Checkpoint-VM $VM -SnapshotName StartingImage }; };






}

Else
{
 
 
 if (($HV_hostname -ne "HOST1") -and ($HV_hostname -ne "HOST2")) {throw "Please use only HOST1 or HOST2 for HV_hostname"}
$prephost= '

#Install-WindowsFeature Hyper-V-Tools,Hyper-V-PowerShell

$Extswitch=New-VMSwitch -Name "External Network" `
             -AllowManagementOS $true `
             -NetAdapterName          `
             ( Get-NetAdapter         `
             |?{ $_.Status -eq "Up" -and $_.NdisPhysicalMedium -eq 14 }).Name

$descr=(bcdedit /enum "{current}"|Select-String "description").Line.TrimStart("description              ")
$MOC=$descr.Substring(0,5)

$volume= Get-Volume |?{$DL=$_.DriveLetter + "`:"; Test-Path -PathType Container  -path "$DL\Program Files\Microsoft Learning\$MOC" }
$DL=$volume.DriveLetter+ "`:"

$path = "c:\Program Files\Microsoft Learning"
$path1 = "$DL\Program Files\Microsoft Learning"
cmd /c "mklink" /d /j $path $path1


if($descr|Select-String "$MOC.*Host.?\.vhd.?")
{
$VMpath ="C:\Program Files\Microsoft Learning\$MOC\Drives"
$VMpathxml =Get-ChildItem $VMpath -include *.xml -ea SilentlyContinue -Recurse -File |Where-Object {$_.Directory -notlike "*VersionB*"}

}

if($descr|Select-String "$MOC.*Host.?B\.vhd.?")
{
$VMpath ="C:\Program Files\Microsoft Learning\$MOC\Drives\VersionB"
$VMpathxml =Get-ChildItem $VMpath -include *.xml -ea SilentlyContinue -Recurse -File |Where-Object {$_.Directory -like "*VersionB*"}

}


if($descr|Select-String ".*HOST1.*") { $batpath =Get-ChildItem $VMpath -ea SilentlyContinue -File |Where-Object {$_.Name -like "*HOST1*.bat"} }
if($descr|Select-String ".*HOST2.*") { $batpath =Get-ChildItem $VMpath -ea SilentlyContinue -File |Where-Object {$_.Name -like "*HOST2*.bat"} }



Write-Host Lets start HOST bat files

$batpath| foreach-object {

  Write-Host Starting Bat File $_.FullName
  Start-Process $ENV:SystemRoot\system32\cmd.exe -argumentlist ("/c " +"`"" + $_.FullName + "`""+ "<nul >nul 2>&1") -WindowStyle Hidden
}


# Lets Import all Virtual machines
foreach ($pathxml in $VMpathxml.Fullname)
    {
  
	Write-Host importing $pathxml
    Import-VM -Path $pathxml -ErrorAction SilentlyContinue -Register

    }
}


#If we had booted in HOST default VersionA, So Lets find other VersionB host boot option and reboot once in it

if($descr|Select-String "$MOC.*Host.?\.vhd.?" )
{

$id = bcdedit /enum | Select-String "^description +$MOC.*Host.?B\.vhd.?" -context 3,0|% {$_.Context.Precontext[0] -replace "^identifier +"}
bcdedit /bootsequence $id
}

# rearming windows host
@cscript //nologo %windir%\System32\slmgr.vbs /rearm


# and finally kill self after all work done and reboot.
Remove-Item $MyInvocation.InvocationName
Restart-Computer
#$descr="20246D-LON-HOST1.vhd"
#$descr="20246D-LON-HOST1B.vhd"
'

$startps = '
Powershell.exe -executionpolicy bypass -File c:\prephost.ps1
rem killing myself
del /f /q %0
'

# Lets copy Host vhds to boot from it.
# Lets make Source Host vhds list from fileshare in an array.
 $sourcehostvhd=@()

$VHDName="$MOCN" + "-LON-" + "$HV_hostname" + ".vhd"
$VHDNameB="$MOCN" + "-LON-" + "$HV_hostname" + "B" + ".vhd"
$vhdpaths= @(("$SourcePath"+ "\Base\" + "$VHDName"),("$SourcePath"+ "\Base\" + "$VHDNameB"))

foreach ($vhdpath in $vhdpaths)
{

    if (Test-Path $vhdpath)
    {
    $i = get-item -path $vhdpath
    $sourcehostvhd += $i
    }
}

# Lets copy Source host vhd files from fileshare.

$hostvhd = @()
foreach ($sourcevhd in $sourcehostvhd)
{
$vhdPath = "$MSDir" +"\Base\" + $sourcevhd.Name

Start-BitsTransfer -Source "$sourcevhd" -Destination "$MSDir\Base" -Description "to $vhdPath" -DisplayName "Copying file $sourcevhd"
$hostvhd += get-item -Path $vhdPath

}


# Lets convert host vhd files to new vhdx format.

if(!($Norepack))
{
    $hostvhdx = @()
    foreach ($vhd in $hostvhd)
        {
        $hostvhdxpath = convert-vhd-my ($vhd.FullName)
        $i = get-item -Path $hostvhdxpath 
        $hostvhdx += $i 
        
        if($vhddeleteafterrepack)
            { Remove-Item $vhd }
        }
    $hostvhd = $hostvhdx

}

#Lets make boot menu entry for all our Host vhd files to boot from
foreach ($vhd in $hostvhd)
    {
    #Lets add all boot menu entry for this vhd 
    $bootdescr = $vhd.Name
    
    #remove all old vhd boot menu item because it maybe wrong configured
    $ids=get-bcdeditidofdescr $vhd.Name
    foreach ($id in $ids) { bcdedit.exe /delete "$id"  };

    Invoke-Expression "chcp 437 >null"
    $Drive = Split-Path -Path $vhd.FullName -Qualifier
    $UnQualifiedPath = Split-Path -Path $vhd.FullName -NoQualifier
    $Copy = bcdedit /copy '{default}' /d $vhd.Name
    $CLSID = [regex]::match($Copy,"{.*}").Value
    bcdedit /set $CLSID device vhd=[$Drive]""$UnQualifiedPath""
    bcdedit /set $CLSID osdevice vhd=[$Drive]""$UnQualifiedPath""
    bcdedit /set $CLSID detecthal on
    bcdedit /set $CLSID locale en-us

    }

#Lets prepare host vhd files to boot from.
foreach ($vhd in $hostvhd)
    {
    prepare-hostvhd $vhd
    }

if($AutoRebootTo -ne $null)
    {
    $id=get-bcdeditidofdescr $AutoRebootTo
    bcdedit /bootsequence $id
    Restart-Computer
    }

}