<#
Windows 10/11 gaming setup
Installs: Windows updates, the newest NVIDIA or AMD GPU driver, the AMD chipset
          driver (or Intel's driver assistant), the newest ASUS mainboard drivers
          that match this PC's hardware, game runtimes, Steam, Battle.net and a
          few gaming settings. More apps with the flags below.
It checks what is already set up first and only does what is missing, so it is
safe to re-run at any time.

Easiest: double-click windows-gaming-setup.cmd (it asks for admin rights).
Or in PowerShell:  powershell -ExecutionPolicy Bypass -File .\windows-gaming-setup.ps1
  -Check      show what is installed/active and change nothing (no admin needed)
  -Guide      only write the instructions file (no admin needed)
  -NoUpdate   skip Windows Update
  -NoDrivers  skip the GPU, chipset and mainboard drivers
  -NoApps     skip runtimes and launchers
  -NoTweaks   skip the gaming settings
  App flags (combine as you like, -All for everything):
  -Gaming     more launchers: Epic Games, EA app, Ubisoft Connect, GOG Galaxy
  -Tuning     MSI Afterburner + RivaTuner, HWiNFO, CPU-Z, GPU-Z
  -Riot       Valorant, League of Legends
  -Other      Display Driver Uninstaller, OBS Studio
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$Guide,
  [switch]$NoUpdate,
  [switch]$NoDrivers,
  [switch]$NoApps,
  [switch]$NoTweaks,
  [switch]$Gaming,
  [switch]$Tuning,
  [switch]$Riot,
  [switch]$Other,
  [switch]$All,
  [switch]$Elevated   # set by the script itself when it restarts as admin
)

# Native tools (winget, 7z) write to stderr; "Stop" would turn that into errors
# in Windows PowerShell 5.1. Failures are checked by exit code instead.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads 10x slower in PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Mode = 'apply'
if ($Guide) { $Mode = 'guide' }
if ($Check) { $Mode = 'check' }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($Mode -eq 'apply' -and -not (Test-Admin)) {
  Write-Host 'Asking for admin rights...'
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
  foreach ($k in $PSBoundParameters.Keys) { if ($k -ne 'Elevated') { $argList += "-$k" } }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
  exit
}

$ScriptDir = Split-Path -Parent $PSCommandPath
$GuideFile = Join-Path $ScriptDir 'windows-gaming-guide.txt'
$LogFile   = Join-Path $ScriptDir 'windows-gaming-setup.log'
$Downloads = Join-Path $env:TEMP 'windows-gaming-setup'
$PF86      = ${env:ProgramFiles(x86)}

$script:NeedReboot = $false
$script:Failed = New-Object System.Collections.Generic.List[string]
$script:Manual = New-Object System.Collections.Generic.List[string]

function Step($t) { Write-Host ''; Write-Host "==> $t" -ForegroundColor Cyan }
function Skip($t) { Write-Host "    already done: $t" }
function Info($t) { Write-Host "    $t" }
function Warn($t) { Write-Host "    ! $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "    ! $t" -ForegroundColor Red; $script:Failed.Add($t) }

# App list ----------------------------------------------------------------
# Edit freely. Group: base = always, the others only with their flag (or -All).
# Id:       winget package id (check one with:  winget search <name>)
# Path:     file that proves the app is installed (faster than asking winget)
# Args:     extra winget arguments
# Fallback: the vendor's own download, used if winget fails (for example when the
#           vendor replaced the installer and winget's checksum no longer matches)
$Apps = @(
  @{ Group = 'base';   Name = 'Visual C++ runtime 2015-2022 (64-bit)'; Id = 'Microsoft.VCRedist.2015+.x64' }
  @{ Group = 'base';   Name = 'Visual C++ runtime 2015-2022 (32-bit)'; Id = 'Microsoft.VCRedist.2015+.x86' }
  @{ Group = 'base';   Name = 'DirectX legacy runtime (older games)';  Id = 'Microsoft.DirectX'
     Path = "$env:SystemRoot\System32\d3dx9_43.dll" }
  @{ Group = 'base';   Name = '.NET 8 Desktop Runtime';  Id = 'Microsoft.DotNet.DesktopRuntime.8'
     Path = "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App\8.*" }
  @{ Group = 'base';   Name = '.NET 10 Desktop Runtime'; Id = 'Microsoft.DotNet.DesktopRuntime.10'
     Path = "$env:ProgramFiles\dotnet\shared\Microsoft.WindowsDesktop.App\10.*" }
  @{ Group = 'base';   Name = '7-Zip'; Id = '7zip.7zip'; Path = "$env:ProgramFiles\7-Zip\7z.exe" }
  @{ Group = 'base';   Name = 'Steam'; Id = 'Valve.Steam'
     Path = "$PF86\Steam\steam.exe"
     Fallback = @{ Url = 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe'; Signer = 'Valve'; Args = '/S' } }
  @{ Group = 'base';   Name = 'Battle.net'; Id = 'Blizzard.BattleNet'
     Path = "$PF86\Battle.net\Battle.net Launcher.exe"
     Args = @('--location', "$PF86\Battle.net")
     Fallback = @{ Url = 'https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe'; Signer = 'Blizzard'
                   Args = "--lang=enUS --installpath=`"$PF86\Battle.net`"" } }

  @{ Group = 'gaming'; Name = 'Epic Games Launcher'; Id = 'EpicGames.EpicGamesLauncher' }
  @{ Group = 'gaming'; Name = 'EA app';              Id = 'ElectronicArts.EADesktop' }
  @{ Group = 'gaming'; Name = 'Ubisoft Connect';     Id = 'Ubisoft.Connect' }
  @{ Group = 'gaming'; Name = 'GOG Galaxy';          Id = 'GOG.Galaxy' }

  @{ Group = 'tuning'; Name = 'MSI Afterburner';     Id = 'Guru3D.Afterburner' }
  @{ Group = 'tuning'; Name = 'RivaTuner Statistics Server (Afterburner overlay)'; Id = 'Guru3D.RTSS' }
  @{ Group = 'tuning'; Name = 'HWiNFO';              Id = 'REALiX.HWiNFO' }
  @{ Group = 'tuning'; Name = 'CPU-Z';               Id = 'CPUID.CPU-Z' }
  @{ Group = 'tuning'; Name = 'GPU-Z';               Id = 'TechPowerUp.GPU-Z' }

  # Riot ids are per region: RiotGames.Valorant.<EU|NA|AP|KR|BR|LATAM>, RiotGames.LeagueOfLegends.<EUW|EUNE|NA|...>
  @{ Group = 'riot';   Name = 'Valorant (EU)';           Id = 'RiotGames.Valorant.EU' }
  @{ Group = 'riot';   Name = 'League of Legends (EUW)'; Id = 'RiotGames.LeagueOfLegends.EUW' }

  @{ Group = 'other';  Name = 'Display Driver Uninstaller'; Id = 'Wagnardsoft.DisplayDriverUninstaller' }
  @{ Group = 'other';  Name = 'OBS Studio';                 Id = 'OBSProject.OBSStudio' }
)
# Which flag turns on which group, and the heading in the report.
$AppGroups = [ordered]@{
  base   = @{ On = $true;            Title = 'Runtimes and launchers' }
  gaming = @{ On = [bool]($Gaming -or $All); Title = 'More launchers (-Gaming)' }
  tuning = @{ On = [bool]($Tuning -or $All); Title = 'Tuning and monitoring (-Tuning)' }
  riot   = @{ On = [bool]($Riot -or $All);   Title = 'Riot games (-Riot)' }
  other  = @{ On = [bool]($Other -or $All);  Title = 'Other tools (-Other)' }
}

# winget exit codes that mean "fine": already installed, no newer version,
# installed but needs a reboot to finish.
$WingetOk     = @(0, -1978335135, -1978335189)
$WingetReboot = @(-1978334967, -1978334966)

# Facts the checks and the setup steps share ------------------------------
function Get-Reg($path, $name) { (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }

function Get-Board {
  $b = Get-CimInstance Win32_BaseBoard
  $bios = Get-CimInstance Win32_BIOS
  [pscustomobject]@{
    Maker   = "$($b.Manufacturer)".Trim()
    Model   = "$($b.Product)".Trim()
    Bios    = "$($bios.SMBIOSBIOSVersion)".Trim()
    BiosDate = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { '?' }
  }
}
function Get-Cpu { Get-CimInstance Win32_Processor | Select-Object -First 1 }
function Test-AmdCpu { (Get-Cpu).Manufacturer -eq 'AuthenticAMD' }
function Test-X3D { (Get-Cpu).Name -match 'X3D' }
function Test-Laptop { [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) }
function Test-AsusBoard { (Get-Board).Maker -match 'ASUS' }
function Get-BoardSupportUrl {
  $b = Get-Board
  if (Test-AsusBoard) { return "https://www.asus.com/supportonly/$($b.Model -replace ' ', '-')/helpdesk_download/" }
  'https://www.bing.com/search?q=' + [uri]::EscapeDataString("$($b.Maker) $($b.Model) support drivers BIOS")
}

# Real GPUs only (PCI devices). A GPU without a driver shows up as
# "Microsoft Basic Display Adapter", so the vendor comes from the PCI id.
function Get-Gpus {
  Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -like 'PCI\*' } | ForEach-Object {
    $vendor = 'Other'
    if ($_.PNPDeviceID -match 'VEN_10DE') { $vendor = 'NVIDIA' }
    elseif ($_.PNPDeviceID -match 'VEN_1002') { $vendor = 'AMD' }
    elseif ($_.PNPDeviceID -match 'VEN_8086') { $vendor = 'Intel' }
    # Without a vendor driver the name is "Microsoft Basic Display Adapter" (translated
    # on non-English Windows), so a real driver shows as the vendor's name.
    $named = $_.Name -match 'NVIDIA|AMD|Radeon|Intel|Arc'
    [pscustomobject]@{ Vendor = $vendor; Name = $_.Name; DriverVersion = $_.DriverVersion; HasDriver = $named; Hz = $_.CurrentRefreshRate }
  }
}
# The GPU this script installs a driver for. NVIDIA wins over AMD so the iGPU of
# a Ryzen CPU next to a GeForce card does not count (Windows Update covers the iGPU).
function Get-MainGpuVendor {
  $v = @(Get-Gpus | ForEach-Object { $_.Vendor })
  foreach ($x in 'NVIDIA', 'AMD', 'Intel') { if ($v -contains $x) { return $x } }
  return 'None'
}

# NVIDIA driver version from the Windows one: 32.0.16.2114 -> 621.14
function Get-NvidiaInstalled {
  $g = Get-Gpus | Where-Object { $_.Vendor -eq 'NVIDIA' -and $_.HasDriver } | Select-Object -First 1
  if (-not $g) { return $null }
  $p = $g.DriverVersion.Split('.')
  $d = $p[2] + $p[3].PadLeft(4, '0')
  $d = $d.Substring($d.Length - 5)
  [version]('{0}.{1}' -f $d.Substring(0, 3), $d.Substring(3))
}

# Newest Game Ready driver from NVIDIA's own driver search (the same one the
# website uses). The desktop package is the same for every current GeForce card,
# so a GPU that has no driver yet (no name) uses the RTX 5090 entry.
$script:NvLatest = $null
function Get-NvidiaLatest {
  if ($script:NvLatest) { return $script:NvLatest }
  try {
    $g = Get-Gpus | Where-Object { $_.Vendor -eq 'NVIDIA' } | Select-Object -First 1
    $short = $g.Name -replace '^NVIDIA ', ''
    [xml]$x = (Invoke-WebRequest -UseBasicParsing -ErrorAction Stop 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3').Content
    $all = $x.LookupValueSearch.LookupValues.LookupValue
    $hit = $all | Where-Object { $_.Name -eq $g.Name -or $_.Name -eq $short } | Select-Object -First 1
    if (-not $hit -and -not (Test-Laptop)) {
      $hit = $all | Where-Object { $_.Name -eq 'NVIDIA GeForce RTX 5090' } | Select-Object -First 1
    }
    if (-not $hit) { return $null }
    $u = 'https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php' +
         "?func=DriverManualLookup&psid=$($hit.ParentID)&pfid=$($hit.Value)&osID=57&languageCode=1033" +
         '&beta=null&isWHQL=1&dltype=-1&dch=1&upCRD=0'
    $r = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop $u
    $info = @($r.IDS)[0].downloadInfo
    $script:NvLatest = [pscustomobject]@{ Version = [version]$info.Version; Url = [uri]::UnescapeDataString($info.DownloadURL) }
  } catch { Warn "NVIDIA driver search failed: $($_.Exception.Message)" }
  return $script:NvLatest
}

# AMD ----------------------------------------------------------------------
$AmdGpuPage     = 'https://www.amd.com/en/support/download/drivers.html'
$AmdChipsetPage = 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/x870e.html'

function Find-AmdLink($page, $pattern) {
  try {
    $html = (Invoke-WebRequest -UseBasicParsing -ErrorAction Stop $page).Content
    $m = [regex]::Matches($html, $pattern) | ForEach-Object { $_.Value } | Sort-Object -Unique
    return @($m)[-1]
  } catch { return $null }
}
function Get-AmdChipsetInstalled {
  $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $e = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'AMD Chipset Software*' } | Select-Object -First 1
  if ($e -and $e.DisplayVersion) { try { return [version]$e.DisplayVersion } catch {} }
  return $null
}
$script:ChipLatest = $null
function Get-AmdChipsetLatest {
  if ($script:ChipLatest) { return $script:ChipLatest }
  # The same chipset package covers every AM4 and AM5 board.
  $url = Find-AmdLink $AmdChipsetPage 'https://drivers\.amd\.com/drivers/amd_chipset_software_[0-9.]+\.exe'
  if ($url -and $url -match '_([0-9.]+)\.exe$') {
    $script:ChipLatest = [pscustomobject]@{ Version = [version]$Matches[1]; Url = $url }
  }
  return $script:ChipLatest
}
function Test-AmdSoftware { Test-Path "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe" }

# ASUS mainboard drivers -------------------------------------------------------
# The same driver list the ASUS support page shows, read from ASUS's own support
# API. Every ASUS driver zip has an AsusSetup.ini that names the hardware it is
# for and its silent install command (ASUS DriverHub uses the same file). A
# package is only installed when one of its hardware ids is in this PC and the
# installed driver is older. Each package is recorded in $AsusStateFile, so it
# is downloaded once and a later run only looks at packages ASUS added since.
#
# Left out: chipset (installed from AMD directly, newer), GPU drivers, BIOS,
# RAID and the utilities (Armoury Crate, AI Advisor, ...).
$AsusSkip = 'VGA|Graphic|Chipset|BIOS|Firmware|SATA|RAID|Software|Utilit|Manual'
$AsusStateFile = Join-Path $env:ProgramData 'windows-gaming-setup\asus-drivers.txt'

$script:AsusList = $null
function Get-AsusPackages {
  if ($null -ne $script:AsusList) { return $script:AsusList }
  $script:AsusList = @()
  try {
    $model = (Get-Board).Model
    $m = [uri]::EscapeDataString($model)
    $r = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop "https://www.asus.com/support/webapi/Product/CheckModelExists?website=global&model=$m"
    $pdid = $r.Result.Obj.productId
    if (-not $pdid) { Warn "ASUS support does not know the model '$model'"; return $script:AsusList }
    $osid = if ([Environment]::OSVersion.Version.Build -ge 22000) { 52 } else { 45 }   # Windows 11 / 10, 64-bit
    $d = Invoke-RestMethod -UseBasicParsing -ErrorAction Stop "https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=global&model=$m&pdid=$pdid&osid=$osid&cpu="
    $seen = @{}
    foreach ($cat in $d.Result.Obj) {
      if ($cat.Name -match $AsusSkip) { continue }
      $files = $cat.Files | Sort-Object -Descending {
        try { [datetime]::ParseExact($_.ReleaseDate, 'yyyy/MM/dd', [Globalization.CultureInfo]::InvariantCulture) } catch { [datetime]::MinValue } }
      foreach ($f in $files) {
        $url = ($f.DownloadUrl.Global -split '\?')[0]
        $file = $url -replace '^.*/', ''
        if ($file -notmatch '\.zip$') { continue }
        # Newest package per category and chip maker (the first word of the title):
        # "Wireless|Realtek" and "Wireless|MediaTek" are both kept, because a board
        # can ship with either chip; older Realtek Wi-Fi packages are dropped.
        $family = $cat.Name + '|' + (($f.Title.Trim() -split '\s+')[0]).ToLower()
        if ($seen.ContainsKey($family)) { continue }
        $seen[$family] = $true
        $script:AsusList += [pscustomobject]@{
          Category = $cat.Name; Title = $f.Title.Trim(); Version = $f.Version; Url = $url; Sha256 = $f.sha256; File = $file }
      }
    }
  } catch { Warn "ASUS driver list failed: $($_.Exception.Message)" }
  return $script:AsusList
}
function Get-AsusState {
  $h = @{}
  if (Test-Path $AsusStateFile) {
    foreach ($l in Get-Content $AsusStateFile) { $p = $l.Split("`t"); if ($p.Count -ge 2) { $h[$p[0]] = $p[1] } }
  }
  return $h
}
function Add-AsusState($file, $outcome) {
  New-Item -ItemType Directory -Force -Path (Split-Path $AsusStateFile) | Out-Null
  Add-Content -Path $AsusStateFile -Value "$file`t$outcome"
}
function Get-AsusPending {
  $state = Get-AsusState
  @(Get-AsusPackages | Where-Object { -not $state.ContainsKey($_.File) })
}
function ConvertTo-Version($v) {
  try { return [version]("$v".Trim()) } catch { return $null }
}

# Windows Update -----------------------------------------------------------
# Everything Windows Update offers, including optional driver updates (often
# few or none for mainboards; the ASUS step covers those).
# GPU drivers of the main GPU are left out: the GPU step installs the newer
# vendor driver and Windows Update would otherwise offer an older one.
function Get-WindowsUpdates {
  $gpuMaker = switch (Get-MainGpuVendor) { 'NVIDIA' { 'NVIDIA' } 'AMD' { 'Advanced Micro Devices|AMD|ATI' } default { '^$' } }
  $session = New-Object -ComObject Microsoft.Update.Session
  $result = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
  $list = @()
  foreach ($u in $result.Updates) {
    if ($u.Type -eq 2 -and $u.DriverClass -eq 'Display' -and $u.DriverManufacturer -match $gpuMaker -and -not $NoDrivers) { continue }
    if ($u.Type -eq 1 -and $u.BrowseOnly) { continue }   # optional preview updates
    $list += $u
  }
  return $list
}
$script:WuPending = $null
function Get-WuPendingCached {
  if ($null -eq $script:WuPending) {
    try { $script:WuPending = @(Get-WindowsUpdates) } catch { $script:WuPending = @(); Warn "Windows Update search failed: $($_.Exception.Message)" }
  }
  return $script:WuPending
}

function Test-RebootPending {
  (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
  (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

# Apps ---------------------------------------------------------------------
function Test-Winget { [bool](Get-Command winget.exe -ErrorAction SilentlyContinue) }
function Test-App($app) {
  if ($app.Path -and (Test-Path $app.Path)) { return $true }
  if (-not (Test-Winget)) { return $false }
  & winget list --id $app.Id --exact --accept-source-agreements --disable-interactivity *> $null
  return ($LASTEXITCODE -eq 0)
}
function Get-SelectedApps {
  $Apps | Where-Object { $AppGroups[$_.Group].On }
}

# Gaming settings ------------------------------------------------------------
$RegGameBar = 'HKCU:\Software\Microsoft\GameBar'
$RegDvr1    = 'HKCU:\System\GameConfigStore'
$RegDvr2    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$RegGfx     = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$RegDxUser  = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$RegMouse   = 'HKCU:\Control Panel\Mouse'
$RegPower   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
$RegTime    = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
$BalancedPlan = '381b4222-f694-41f0-9685-ff5bb260df2e'

function Get-DxSettings {
  $map = [ordered]@{}
  $cur = Get-Reg $RegDxUser 'DirectXUserGlobalSettings'
  if ($cur) { foreach ($kv in $cur.Split(';')) { if ($kv -match '^(.+?)=(.*)$') { $map[$Matches[1]] = $Matches[2] } } }
  return $map
}
function Test-DxSettings { $m = Get-DxSettings; $m['SwapEffectUpgradeEnable'] -eq '1' -and $m['VRROptimizeEnable'] -eq '1' }
function Test-MouseAccelOff { (Get-Reg $RegMouse 'MouseSpeed') -eq '0' -and (Get-Reg $RegMouse 'MouseThreshold1') -eq '0' -and (Get-Reg $RegMouse 'MouseThreshold2') -eq '0' }
function Test-DvrOff { (Get-Reg $RegDvr1 'GameDVR_Enabled') -eq 0 -and (Get-Reg $RegDvr2 'AppCaptureEnabled') -eq 0 }
function Get-ActivePlan { if ((powercfg /getactivescheme) -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $Matches[1] } }
# A Linux partition on any disk means dual boot (Fedora keeps the hardware clock in UTC).
function Test-DualBoot {
  [bool](Get-Partition -ErrorAction SilentlyContinue | Where-Object { $_.GptType -eq '{0fc63daf-8483-4772-8e79-3d69d8477de4}' })
}

# Info shown in the report but not counted -------------------------------------
function Get-SecureBootState {
  try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { 'on' } else { 'off' } } catch { 'unknown (needs admin, or legacy BIOS)' }
}
function Get-TpmState {
  try { $t = Get-CimInstance -Namespace root\cimv2\Security\MicrosoftTpm -ClassName Win32_Tpm -ErrorAction Stop
        if ($t.IsEnabled_InitialValue) { "on (version $($t.SpecVersion.Split(',')[0]))" } else { 'off' } } catch { 'unknown (needs admin)' }
}
function Get-ReBarState {
  $smi = "$env:SystemRoot\System32\nvidia-smi.exe"
  if (-not (Test-Path $smi)) { return $null }
  $q = & $smi -q -d MEMORY 2>$null | Out-String
  if ($q -match 'BAR1 Memory Usage\s+Total\s+:\s+(\d+) MiB') {
    if ([int]$Matches[1] -gt 256) { return 'on' } else { return 'OFF (enable "Resizable BAR" / "Above 4G decoding" in the BIOS)' }
  }
  return $null
}
function Get-RamInfo {
  $m = @(Get-CimInstance Win32_PhysicalMemory)
  $gb = [math]::Round((($m | Measure-Object Capacity -Sum).Sum) / 1GB)
  "$gb GB, running at $(($m | Select-Object -First 1).ConfiguredClockSpeed) MT/s"
}

# Status report ----------------------------------------------------------------
$script:Lines = New-Object System.Collections.Generic.List[string]
$script:NOk = 0; $script:NMissing = 0; $script:NReboot = 0
function Row($tag, $text, $color) {
  $line = '  {0,-8} {1}' -f $tag, $text
  $script:Lines.Add($line)
  if ($color) { Write-Host $line -ForegroundColor $color } else { Write-Host $line }
}
function Section($t) { $script:Lines.Add(''); $script:Lines.Add(" $t"); Write-Host ''; Write-Host " $t" }
function Pass($t)    { Row 'OK' $t; $script:NOk++ }
function Absent($t)  { Row 'MISSING' $t 'Yellow'; $script:NMissing++ }
function WaitReboot($t) { Row 'REBOOT' $t 'Yellow'; $script:NReboot++ }
function Item($label, [scriptblock]$test) { if (& $test) { Pass $label } else { Absent $label } }
function Note($label) { Row 'info' $label }

function Report {
  $script:Lines.Clear(); $script:NOk = 0; $script:NMissing = 0; $script:NReboot = 0
  $os = Get-CimInstance Win32_OperatingSystem
  $ver = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion'
  $b = Get-Board
  $head = @(
    " $($os.Caption) $ver (build $($os.BuildNumber))"
    " Mainboard: $($b.Maker) $($b.Model), BIOS $($b.Bios) from $($b.BiosDate)"
    " CPU: $((Get-Cpu).Name.Trim())"
  )
  foreach ($g in Get-Gpus) { $head += " GPU: $($g.Name) (driver $($g.DriverVersion))" }
  foreach ($l in $head) { $script:Lines.Add($l); Write-Host $l }

  Section 'Base'
  Item 'winget (App Installer)' { Test-Winget }
  if (Test-RebootPending) { WaitReboot 'Windows is waiting for a reboot' } else { Pass 'No reboot pending' }
  if (-not $NoUpdate) {
    Write-Host '    (asking Windows Update, this can take a minute)'
    $wu = @(Get-WuPendingCached)
    $drv = @($wu | Where-Object { $_.Type -eq 2 }).Count
    $sw = $wu.Count - $drv
    if ($wu.Count -eq 0) { Pass 'Windows Update: nothing pending' }
    else { Absent "Windows Update: $sw system and $drv driver update(s) pending" }
  }

  if (-not $NoDrivers) {
    Section 'Drivers'
    switch (Get-MainGpuVendor) {
      'NVIDIA' {
        $have = Get-NvidiaInstalled; $new = Get-NvidiaLatest
        $label = "NVIDIA driver $(if ($have) { $have } else { 'not installed' })"
        if ($new) { $label += " (newest: $($new.Version))" }
        if ($have -and (-not $new -or $have -ge $new.Version)) { Pass $label } else { Absent $label }
      }
      'AMD' {
        Item 'AMD Software: Adrenalin Edition' { Test-AmdSoftware }
      }
      'Intel' { Item 'Intel Driver & Support Assistant' { Test-App @{ Id = 'Intel.IntelDriverAndSupportAssistant' } } }
      default { Note 'No graphics card found' }
    }
    if (Test-AmdCpu) {
      $have = Get-AmdChipsetInstalled; $new = Get-AmdChipsetLatest
      $label = "AMD chipset driver $(if ($have) { $have } else { 'not installed' })"
      if ($new) { $label += " (newest: $($new.Version))" }
      if ($have -and (-not $new -or $have -ge $new.Version)) { Pass $label } else { Absent $label }
    } else {
      Item 'Intel Driver & Support Assistant (chipset)' { Test-App @{ Id = 'Intel.IntelDriverAndSupportAssistant' } }
    }
    if (Test-AsusBoard) {
      $all = @(Get-AsusPackages)
      $pending = @(Get-AsusPending)
      if ($all.Count -eq 0) { Absent 'ASUS mainboard drivers (could not read the ASUS driver list)' }
      elseif ($pending.Count -eq 0) { Pass "ASUS mainboard drivers ($($all.Count) packages checked)" }
      else {
        Note 'ASUS packages not checked yet (only the ones for this PC get installed):'
        foreach ($p in $pending) { Absent "ASUS $($p.Category): $($p.Title)" }
      }
    } else {
      Note "Mainboard drivers: not automated for $((Get-Board).Maker), see the support link below"
    }
  }

  if (-not $NoApps) {
    foreach ($grp in $AppGroups.Keys) {
      $info = $AppGroups[$grp]
      Section $info.Title
      foreach ($a in @($Apps | Where-Object { $_.Group -eq $grp })) {
        if ($info.On) { Item $a.Name { Test-App $a } }
        elseif (Test-App $a) { Row 'OK' $a.Name }
        else { Row 'off' $a.Name }
      }
    }
  }

  if (-not $NoTweaks) {
    Section 'Gaming settings'
    Item 'Game Mode on' { (Get-Reg $RegGameBar 'AutoGameModeEnabled') -ne 0 }
    $hags = Get-Reg $RegGfx 'HwSchMode'
    if ($hags -eq 2) { Pass 'Hardware-accelerated GPU scheduling (needed for DLSS Frame Generation)' }
    else { Absent 'Hardware-accelerated GPU scheduling (needed for DLSS Frame Generation)' }
    Item 'Optimizations for windowed games + VRR' { Test-DxSettings }
    Item 'Background game recording off (Game Bar itself stays)' { Test-DvrOff }
    Item 'Mouse acceleration off' { Test-MouseAccelOff }
    Item 'Fast Startup off' { (Get-Reg $RegPower 'HiberbootEnabled') -eq 0 }
    if (Test-X3D) { Item 'Balanced power plan (needed by the X3D V-Cache driver)' { (Get-ActivePlan) -eq $BalancedPlan } }
    if (Test-DualBoot) { Item 'Clock in UTC (dual boot with Linux)' { (Get-Reg $RegTime 'RealTimeIsUniversal') -eq 1 } }
  }

  Section 'Info (check in the BIOS if needed, see the guide)'
  Note "Secure Boot: $(Get-SecureBootState)   TPM: $(Get-TpmState)"
  Note "RAM: $(Get-RamInfo) (if your kit is rated higher, enable EXPO/XMP)"
  $rebar = Get-ReBarState
  if ($rebar) { Note "Resizable BAR: $rebar" }
  foreach ($g in Get-Gpus) { if ($g.Hz) { Note "$($g.Name): display at $($g.Hz) Hz" } }
  Note "Board drivers and BIOS: $(Get-BoardSupportUrl)"

  $sum = ' Summary: {0} OK, {1} missing, {2} waiting for a reboot' -f $script:NOk, $script:NMissing, $script:NReboot
  $script:Lines.Add(''); $script:Lines.Add($sum); Write-Host ''; Write-Host $sum
}

# Instructions file --------------------------------------------------------------
function Write-GuideFile([switch]$ReuseReport) {
  $b = Get-Board
  $g = @"
WINDOWS GAMING SETUP GUIDE
Written by windows-gaming-setup.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Run the setup:      double-click windows-gaming-setup.cmd
Check the system:   powershell -ExecutionPolicy Bypass -File "$PSCommandPath" -Check
Refresh this file:  powershell -ExecutionPolicy Bypass -File "$PSCommandPath" -Guide
Log of the last run: $LogFile

CONTENTS
  1. What the script does          6. Launcher tips
  2. Keeping drivers up to date    7. Anti-cheat
  3. Mainboard drivers and BIOS    8. Settings changed and how to undo them
  4. BIOS checklist                9. Troubleshooting
  5. NVIDIA / AMD settings        10. Current system state


1. WHAT THE SCRIPT DOES
-----------------------
In this order, skipping everything that is already done:
  - Windows Update: all pending system updates plus any optional driver updates.
    GPU drivers from Windows Update are skipped because the script installs
    the newer one from NVIDIA/AMD.
  - GPU driver:
      NVIDIA  newest Game Ready driver straight from nvidia.com, silent install.
              The NVIDIA App comes with it.
      AMD     AMD's auto-detect installer (picks the right Adrenalin driver).
      Intel   Intel Driver & Support Assistant.
  - Chipset: AMD Chipset Software on Ryzen (includes the X3D V-Cache driver),
    Intel Driver & Support Assistant on Intel.
  - Mainboard drivers (ASUS boards): LAN, Wi-Fi, Bluetooth, audio, USB and
    the rest from the ASUS support page, see section 3.
  - Always: Visual C++ 2015-2022 (32+64-bit), DirectX legacy runtime,
    .NET 8 + 10, 7-Zip, Steam, Battle.net.
  - App flags (combine them, or -All for everything):
      -Gaming   Epic Games, EA app, Ubisoft Connect, GOG Galaxy
      -Tuning   MSI Afterburner + RivaTuner (its overlay), HWiNFO, CPU-Z, GPU-Z
      -Riot     Valorant, League of Legends (EU servers, see the app list)
      -Other    Display Driver Uninstaller, OBS Studio
    Example:  windows-gaming-setup.cmd -Gaming -Tuning
  - Gaming settings, see section 8.

The app list sits at the top of windows-gaming-setup.ps1. Add or remove lines
there; find package ids with:  winget search <name>
Run it again after the reboot: Windows Update often has a second round.


2. KEEPING DRIVERS UP TO DATE
-----------------------------
Re-run the script (or -Check to only look). It compares the installed NVIDIA
and AMD chipset driver with the newest one and only installs when there is a
newer one. For ASUS boards it lists the driver packages ASUS added since the
last run. In between:
  NVIDIA  NVIDIA App > Drivers. "Game Ready" is right for gaming.
  AMD     AMD Software > Settings (gear) > System > Check for updates.
  Apps    winget upgrade --all    (updates everything installed with winget)

Clean GPU driver install (after problems or when switching NVIDIA <-> AMD):
  run with -Other to get Display Driver Uninstaller, boot into Safe Mode,
  run DDU "Clean and restart", then run this script again.


3. MAINBOARD DRIVERS AND BIOS
-----------------------------
Your board: $($b.Maker) $($b.Model), BIOS $($b.Bios) from $($b.BiosDate)
Support page: $(Get-BoardSupportUrl)

ASUS boards: the script reads the same driver list as the ASUS support page
(no DriverHub or Armoury Crate needed). For each chip it takes the newest
package, checks the download against the SHA-256 checksum ASUS publishes, and
installs it silently with ASUS's own install command, but only if:
  - the package is for hardware this PC has (a board can come with a Realtek
    or a MediaTek Wi-Fi chip; only the one you have is installed), and
  - the installed driver is older, or is Windows' generic driver.
Left out on purpose: chipset (comes from AMD directly and is newer), GPU
drivers, BIOS, RAID, and the ASUS utilities (Armoury Crate, AI Advisor).
What was handled is listed in:
  $AsusStateFile
Delete a line there (or the whole file) to make the script look at that
package again.

Other boards (MSI, Gigabyte, ASRock): they have no public driver list, so use
the support page above, or the maker's tool:
  MSI       MSI Center (winget install MSI.MSICenter)
  Gigabyte  Gigabyte Control Center
  ASRock    the support page (Download > Drivers / BIOS)
Update the BIOS from the BIOS itself (ASUS EZ Flash, MSI M-Flash, Gigabyte Q-Flash,
ASRock Instant Flash) with the file on a FAT32 USB stick. A BIOS update resets
the BIOS settings: check section 4 again afterwards.
On Ryzen X3D CPUs a recent BIOS matters: it carries the AGESA updates that make
the V-Cache scheduling work properly.


4. BIOS CHECKLIST
-----------------
  EXPO / XMP          on. Without it RAM runs at its slow default speed.
                      The report shows the speed the RAM runs at now.
  Resizable BAR       on (often "Above 4G Decoding" + "Re-Size BAR Support").
                      The report shows it for NVIDIA cards.
  Secure Boot + TPM   on. Required by some anti-cheats (section 7).
  CSM                 off (needed for Secure Boot and Resizable BAR).
  X3D CPUs            "CPPC" and "CPPC Preferred Cores" = Auto/Enabled.
                      Leave X3D Gaming Mode / core parking settings on Auto.


5. NVIDIA / AMD SETTINGS
------------------------
NVIDIA (NVIDIA App and NVIDIA Control Panel):
  - G-SYNC on (Control Panel > Set up G-SYNC, full screen and windowed).
  - Vertical sync "On" in the Control Panel, off in the games.
  - In games: NVIDIA Reflex "On" (or On + Boost). With G-SYNC + V-Sync + Reflex
    the frame rate stays under the refresh rate by itself.
  - NVIDIA App > Graphics > per game: DLSS overrides (newer DLSS model,
    Frame Generation) for games that ship an old DLSS.
  - Instant replay / recording: NVIDIA App overlay (Alt+Z).
AMD (AMD Software):
  - FreeSync on (Display tab), Radeon Anti-Lag on, Radeon Chill off for testing.
  - HYPR-RX profile for a quick "everything on" setup, or set per game.
Both: Settings > Display > Advanced display: pick the highest refresh rate.
The report shows the refresh rate the display runs at now.


6. LAUNCHER TIPS
----------------
  - Put game libraries on the fastest drive. Steam: Settings > Storage.
    Battle.net: Settings > Downloads > Default install location.
  - Battle.net is installed to $PF86\Battle.net.
  - Turn off "start with Windows" in each launcher you do not use daily.
  - EA, Ubisoft and Battle.net games bought on Steam still need their launcher.


7. ANTI-CHEAT
-------------
  - Valorant / League (Vanguard): Windows 11 needs TPM 2.0 and Secure Boot on.
  - Battlefield 6 (Javelin), Call of Duty (Ricochet): Secure Boot on.
  - FACEIT: Memory integrity (Core isolation) may be required. Leave it on.
  - Do not use "debloat" scripts that remove Xbox/Game Bar services: some games
    and the X3D V-Cache driver depend on them.


8. SETTINGS CHANGED AND HOW TO UNDO THEM
----------------------------------------
  Game Mode on
      Settings > Gaming > Game Mode.
  Hardware-accelerated GPU scheduling on (needs a reboot)
      Settings > System > Display > Graphics > Advanced graphics settings.
      Needed for DLSS Frame Generation.
  Optimizations for windowed games + Variable refresh rate on
      Settings > System > Display > Graphics > Advanced graphics settings.
      Gives windowed/borderless DX10/11 games the low latency of full screen.
  Background game recording off (Game Bar and its overlay stay)
      Settings > Gaming > Captures > "Record what happened".
  Mouse acceleration off ("Enhance pointer precision", after sign-out)
      Settings > Bluetooth & devices > Mouse > Additional mouse settings > Pointer Options.
  Fast Startup off
      Control Panel > Power Options > Choose what the power buttons do.
      Fast Startup is half-hibernation: drivers do not fully reload on shutdown
      and a dual-boot Linux sees the Windows drives as locked.
  Balanced power plan (X3D CPUs only)
      AMD's V-Cache driver decides which cores a game uses, and it needs the
      Balanced plan. Other plans can put games on the wrong CCD.
      Control Panel > Power Options.
  Clock in UTC (only if a Linux partition was found)
      Linux keeps the hardware clock in UTC, Windows in local time; without this
      the clock is off by 1-2 hours after switching. Undo:
      reg delete HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation /v RealTimeIsUniversal /f


9. TROUBLESHOOTING
------------------
  "winget is not recognized"
      Microsoft Store > Library > update "App Installer", then run again.
  An app fails to install
      Run the line by hand to see the reason:
        winget install --id <Id> --exact --source winget
      The ids are in the app list at the top of the script.
  An ASUS driver should be installed again
      Delete its line in $AsusStateFile and run the script.
  AMD download opens a web page instead
      AMD sometimes blocks scripted downloads. Click Download on the page that
      opened, run the file, then run the script again.
  X3D: games stutter or use the wrong cores
      Check that "AMD 3D V-Cache Performance Optimizer" exists in services.msc,
      the power plan is Balanced, and Game Bar is not removed.
  Everything the script printed is in the log: $LogFile


10. CURRENT SYSTEM STATE
------------------------
"@
  if (-not $ReuseReport) { Report }
  $g += ($script:Lines -join "`r`n")
  Set-Content -Path $GuideFile -Value $g -Encoding UTF8
}

# --- Modes without changes ------------------------------------------------------
if ($Mode -eq 'check') { Report; exit }
if ($Mode -eq 'guide') { Write-GuideFile; Write-Host "Wrote $GuideFile"; exit }

# --- Apply ----------------------------------------------------------------------
try { Start-Transcript -Path $LogFile -Force | Out-Null } catch {}
New-Item -ItemType Directory -Force -Path $Downloads | Out-Null

# Downloads a file and checks its digital signature, so a blocked download (a web
# page instead of the installer) or a tampered file is never run.
function Get-Installer($url, $signer, $name) {
  if (-not $name) { $name = ($url -split '[/?=&]')[-1] }
  if ($name -notmatch '\.exe$') { $name += '.exe' }
  $out = Join-Path $Downloads $name
  if (-not (Test-Path $out)) {
    Info "downloading $url"
    try { Start-BitsTransfer -Source $url -Destination $out -ErrorAction Stop }
    catch {
      try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out -ErrorAction Stop }
      catch { Warn "download failed: $($_.Exception.Message)"; return $null }
    }
  }
  $sig = Get-AuthenticodeSignature $out
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $signer) {
    Warn "$name is not a valid installer signed by $signer (got: $($sig.Status))"
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    return $null
  }
  return $out
}

function Install-App($app) {
  if (Test-App $app) { Skip $app.Name; return }
  Info "installing $($app.Name)"
  $src = if ($app.Source) { $app.Source } else { 'winget' }
  $a = @('install', '--id', $app.Id, '--exact', '--source', $src, '--silent',
         '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
  if ($app.Args) { $a += $app.Args }
  & winget @a
  $code = $LASTEXITCODE
  if ($WingetOk -contains $code) { return }
  if ($WingetReboot -contains $code) { $script:NeedReboot = $true; return }
  if ($app.Fallback) {
    Warn "winget failed ($code), using the download from the vendor"
    $exe = Get-Installer $app.Fallback.Url $app.Fallback.Signer
    if ($exe) {
      $p = Start-Process -FilePath $exe -ArgumentList $app.Fallback.Args -Wait -PassThru
      if ($p.ExitCode -eq 0) { return }
    }
  }
  Fail "$($app.Name) did not install (winget code $code)"
}

function Ensure-Winget {
  if (Test-Winget) { return $true }
  Info 'winget not found, registering App Installer'
  try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  if (Test-Winget) { return $true }
  Info 'downloading App Installer from Microsoft'
  try {
    $f = Join-Path $Downloads 'AppInstaller.msixbundle'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/getwinget' -OutFile $f -ErrorAction Stop
    Add-AppxPackage -Path $f -ErrorAction Stop
  } catch { Warn $_.Exception.Message }
  return (Test-Winget)
}

Step 'Current state'
Report

Step 'Preparing winget'
if (Ensure-Winget) { & winget source update --disable-interactivity | Out-Null; Info 'winget ready' }
else { Fail 'winget is missing: update "App Installer" in the Microsoft Store, then run again'; $NoApps = [switch]$true }

if (-not $NoUpdate) {
  Step 'Windows Update'
  $list = @(Get-WuPendingCached)   # found by the report above
  if ($list.Count -eq 0) { Skip 'nothing pending' }
  else {
    $session = New-Object -ComObject Microsoft.Update.Session
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $list) { Info $u.Title; if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$coll.Add($u) }
    Info "downloading $($coll.Count) update(s)"
    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
    Info 'installing (this can take a while)'
    $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
    try {
      $r = $inst.Install()
      if ($r.RebootRequired) { $script:NeedReboot = $true }
      for ($i = 0; $i -lt $coll.Count; $i++) {
        # ResultCode 2 = succeeded, 3 = succeeded with errors
        if ($r.GetUpdateResult($i).ResultCode -notin 2, 3) { Fail "Windows Update: $($coll.Item($i).Title)" }
      }
    } catch { Fail "Windows Update install failed: $($_.Exception.Message)" }
    $script:WuPending = $null   # let the final report ask again
  }
}

if (-not $NoDrivers) {
  $gpu = Get-MainGpuVendor
  Step "GPU driver ($gpu)"
  switch ($gpu) {
    'NVIDIA' {
      $have = Get-NvidiaInstalled; $new = Get-NvidiaLatest
      if (-not $new) {
        Fail 'could not find the newest NVIDIA driver, get it from https://www.nvidia.com/Download/index.aspx'
      } elseif ($have -and $have -ge $new.Version) {
        Skip "NVIDIA driver $have"
      } else {
        Info "installing NVIDIA driver $($new.Version) (installed: $(if ($have) { $have } else { 'none' }))"
        Install-App ($Apps | Where-Object { $_.Id -eq '7zip.7zip' })
        $exe = Get-Installer $new.Url 'NVIDIA'
        $sevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
        if ($exe -and (Test-Path $sevenZip)) {
          $dir = Join-Path $Downloads "nvidia-$($new.Version)"
          & $sevenZip x $exe "-o$dir" -y | Out-Null
          Info 'running the NVIDIA installer silently (the screen may flicker)'
          $p = Start-Process -FilePath (Join-Path $dir 'setup.exe') -ArgumentList '-s', '-noreboot', '-noeula' -Wait -PassThru
          if ($p.ExitCode -ne 0) { Warn "NVIDIA installer exit code $($p.ExitCode) (often only means: reboot needed)" }
          $script:NeedReboot = $true
          Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        } elseif ($exe) {
          Info 'running the NVIDIA installer'
          Start-Process -FilePath $exe -Wait
          $script:NeedReboot = $true
        } else { Fail 'NVIDIA driver download failed' }
      }
    }
    'AMD' {
      if (Test-AmdSoftware) { Skip 'AMD Software: Adrenalin Edition (it updates itself)' }
      else {
        $url = Find-AmdLink $AmdGpuPage 'https://drivers\.amd\.com/drivers/installer/[^"''<> ]+minimalsetup[^"''<> ]+\.exe'
        $exe = if ($url) { Get-Installer $url 'Advanced Micro Devices' } else { $null }
        if ($exe) {
          Info 'starting the AMD installer: it finds the right driver, follow its window'
          Start-Process -FilePath $exe -Wait
          $script:NeedReboot = $true
        } else {
          Start-Process $AmdGpuPage
          $script:Manual.Add('AMD GPU driver: click "Download Windows Drivers" on the AMD page that opened and run it')
        }
      }
    }
    'Intel' { Install-App @{ Name = 'Intel Driver & Support Assistant'; Id = 'Intel.IntelDriverAndSupportAssistant' } }
    default { Skip 'no graphics card found' }
  }

  Step 'Chipset driver'
  if (Test-AmdCpu) {
    $have = Get-AmdChipsetInstalled; $new = Get-AmdChipsetLatest
    if ($have -and (-not $new -or $have -ge $new.Version)) { Skip "AMD chipset driver $have" }
    else {
      $exe = if ($new) { Get-Installer $new.Url 'Advanced Micro Devices' } else { $null }
      if ($exe) {
        Info "starting the AMD chipset installer $($new.Version): follow its window"
        Start-Process -FilePath $exe -Wait
        $script:NeedReboot = $true
      } else {
        Start-Process $AmdChipsetPage
        $script:Manual.Add('AMD chipset driver: download "AMD Chipset Drivers" on the AMD page that opened and run it')
      }
    }
  } else {
    Install-App @{ Name = 'Intel Driver & Support Assistant'; Id = 'Intel.IntelDriverAndSupportAssistant' }
    $script:Manual.Add('Intel: open "Intel Driver & Support Assistant" from the Start menu and install what it finds')
  }

  if (Test-AsusBoard) {
    Step 'Mainboard drivers (ASUS)'
    $pending = @(Get-AsusPending)
    if (@(Get-AsusPackages).Count -eq 0) { Fail "could not read the ASUS driver list, get them from $(Get-BoardSupportUrl)" }
    elseif ($pending.Count -eq 0) { Skip 'all ASUS driver packages checked' }
    else {
      # Hardware ids of every device in this PC, and the driver version each one runs.
      $devices = @(Get-CimInstance Win32_PnPEntity | ForEach-Object {
        [pscustomobject]@{ Id = $_.PNPDeviceID; Hw = @(@($_.HardwareID) + @($_.CompatibleID) | Where-Object { $_ } | ForEach-Object { $_.ToUpper() }) } })
      $drv = @{}
      Get-CimInstance Win32_PnPSignedDriver | ForEach-Object {
        if ($_.DeviceID) { $drv[$_.DeviceID] = [pscustomobject]@{ Version = (ConvertTo-Version $_.DriverVersion); Provider = "$($_.DriverProviderName)" } } }

      # Devices a newer package already covered in this run. The list is newest
      # first, so an older package for the same chip is never installed over it.
      $handled = @{}
      foreach ($p in $pending) {
        Info "$($p.Category): $($p.Title)"
        $zip = Join-Path $Downloads $p.File
        if (-not (Test-Path $zip) -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $p.Sha256) {
          try { Start-BitsTransfer -Source $p.Url -Destination $zip -ErrorAction Stop }
          catch { try { Invoke-WebRequest -UseBasicParsing -Uri $p.Url -OutFile $zip -ErrorAction Stop } catch {} }
        }
        if (-not (Test-Path $zip) -or ($p.Sha256 -and (Get-FileHash $zip -Algorithm SHA256).Hash -ne $p.Sha256)) {
          Fail "ASUS $($p.Title): download failed or checksum does not match"
          Remove-Item $zip -Force -ErrorAction SilentlyContinue
          continue
        }
        $dir = Join-Path $Downloads ($p.File -replace '\.zip$', '')
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        $ini = Get-ChildItem $dir -Recurse -Filter 'AsusSetup.ini' | Select-Object -First 1
        $cfg = @{}
        if ($ini) {
          foreach ($l in Get-Content $ini.FullName) {
            if ($l -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*(;;.*)?$' -and -not $cfg.ContainsKey($Matches[1])) { $cfg[$Matches[1]] = $Matches[2] }
          }
        }
        $ids = @("$($cfg['HardwareID'])".Split(',') | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
        if (-not $cfg['SilentInstallRun'] -or $ids.Count -eq 0) {
          Info '  no automatic install in this package, skipped'
          $script:Manual.Add("ASUS $($p.Title): install it from $(Get-BoardSupportUrl)")
          Add-AsusState $p.File 'manual'
          Remove-Item $dir, $zip -Recurse -Force -ErrorAction SilentlyContinue
          continue
        }
        # ASUS lists id prefixes (HDAUDIO\FUNC_01&VEN_10EC&DEV_ = every Realtek codec).
        $match = @($devices | Where-Object { $d = $_; @($d.Hw | Where-Object { $h = $_; @($ids | Where-Object { $h.StartsWith($_) }).Count }).Count })
        if ($match.Count -eq 0) {
          Info '  not for the hardware in this PC'
          Add-AsusState $p.File 'not for this PC'
          Remove-Item $dir, $zip -Recurse -Force -ErrorAction SilentlyContinue
          continue
        }
        $fresh = @($match | Where-Object { -not $handled.ContainsKey($_.Id) })
        foreach ($dv in $match) { $handled[$dv.Id] = $true }
        if ($fresh.Count -eq 0) {
          Info '  a newer package for this hardware was already used'
          Add-AsusState $p.File 'older than another package'
          Remove-Item $dir, $zip -Recurse -Force -ErrorAction SilentlyContinue
          continue
        }
        # Outdated = no driver, Windows' generic driver (Microsoft, whose version
        # numbers are not comparable), or an older vendor driver.
        $want = ConvertTo-Version $(if ($cfg['Version']) { $cfg['Version'] } else { $p.Version })
        $outdated = -not $want
        $haveText = 'none'
        foreach ($dv in $fresh) {
          $cur = $drv[$dv.Id]
          if ($cur -and $cur.Version) { $haveText = "$($cur.Version) ($($cur.Provider))" }
          if (-not $want -or -not $cur -or -not $cur.Version -or $cur.Provider -match 'Microsoft' -or $cur.Version -lt $want) { $outdated = $true }
        }
        if (-not $outdated) {
          Info "  installed driver is already $haveText"
          Add-AsusState $p.File 'already up to date'
          Remove-Item $dir, $zip -Recurse -Force -ErrorAction SilentlyContinue
          continue
        }
        $wd = Join-Path $ini.DirectoryName "$($cfg['SilentInstallPath'])"
        Info "  installing $want silently (installed: $haveText)"
        # Wait for the installer only: -Wait would also wait for every program it
        # starts, which can be a background service that never ends.
        $timeout = 900
        if ("$($cfg['InstallFinishTimeOutSecond'])" -match '^\d+$') { $timeout = [math]::Max(300, [int]$cfg['InstallFinishTimeOutSecond'] * 2) }
        $proc = Start-Process cmd.exe -ArgumentList '/c', $cfg['SilentInstallRun'] -WorkingDirectory $wd -WindowStyle Hidden -PassThru
        $null = $proc.Handle   # PS 5.1 only reports the exit code if the handle was opened
        if ($proc.WaitForExit($timeout * 1000)) { Info "  done (exit code $($proc.ExitCode))" }
        else { Warn "  still running after $timeout s, continuing" }
        Add-AsusState $p.File 'installed'
        $script:NeedReboot = $true
        Remove-Item $dir, $zip -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  } else {
    Step 'Mainboard drivers'
    Info "$((Get-Board).Maker) boards are not automated (only ASUS has a public driver list)."
    $script:Manual.Add("Mainboard drivers: $(Get-BoardSupportUrl)")
  }
}

if (-not $NoApps) {
  Step 'Runtimes, launchers and apps'
  foreach ($a in Get-SelectedApps) { Install-App $a }
}

if (-not $NoTweaks) {
  Step 'Gaming settings'
  function Set-Reg($path, $name, $value, $type, $label) {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    if ("$(Get-Reg $path $name)" -eq "$value") { Skip $label; return }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
    Info "set: $label"
  }
  Set-Reg $RegGameBar 'AutoGameModeEnabled' 1 DWord 'Game Mode on'
  if ((Get-Reg $RegGfx 'HwSchMode') -ne 2) { $script:NeedReboot = $true }
  Set-Reg $RegGfx 'HwSchMode' 2 DWord 'Hardware-accelerated GPU scheduling'
  $dx = Get-DxSettings
  $dx['SwapEffectUpgradeEnable'] = '1'; $dx['VRROptimizeEnable'] = '1'
  $dxValue = (($dx.Keys | ForEach-Object { "$_=$($dx[$_])" }) -join ';') + ';'
  Set-Reg $RegDxUser 'DirectXUserGlobalSettings' $dxValue String 'Optimizations for windowed games + VRR'
  Set-Reg $RegDvr1 'GameDVR_Enabled' 0 DWord 'Background game recording off'
  Set-Reg $RegDvr2 'AppCaptureEnabled' 0 DWord 'Game Bar captures off'
  Set-Reg $RegMouse 'MouseSpeed' '0' String 'Mouse acceleration off (1/3)'
  Set-Reg $RegMouse 'MouseThreshold1' '0' String 'Mouse acceleration off (2/3)'
  Set-Reg $RegMouse 'MouseThreshold2' '0' String 'Mouse acceleration off (3/3)'
  Set-Reg $RegPower 'HiberbootEnabled' 0 DWord 'Fast Startup off'
  if (Test-X3D) {
    if ((Get-ActivePlan) -eq $BalancedPlan) { Skip 'Balanced power plan (X3D)' }
    else { powercfg /setactive $BalancedPlan; Info 'set: Balanced power plan (X3D V-Cache driver needs it)' }
  }
  if (Test-DualBoot) { Set-Reg $RegTime 'RealTimeIsUniversal' 1 DWord 'Clock in UTC (Linux partition found)' }
}

Step 'Final state'
Report
Write-GuideFile -ReuseReport

Step 'Done'
if ($script:Failed.Count) {
  Write-Host ' These did not work (details above and in the log):' -ForegroundColor Red
  foreach ($f in $script:Failed) { Write-Host "  - $f" }
}
if ($script:Manual.Count) {
  Write-Host ' Still to do by hand:' -ForegroundColor Yellow
  foreach ($m in $script:Manual) { Write-Host "  - $m" }
}
Write-Host " Board drivers and BIOS: $(Get-BoardSupportUrl)"
Write-Host " Guide: $GuideFile"
if ($script:NeedReboot -or (Test-RebootPending)) {
  Write-Host ' Reboot now, then run the script again: Windows Update often has a second round.' -ForegroundColor Yellow
}
try { Stop-Transcript | Out-Null } catch {}
if ($Elevated) { Read-Host ' Press Enter to close' | Out-Null }
