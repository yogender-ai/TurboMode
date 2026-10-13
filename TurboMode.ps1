# ============================================================
#  TURBO MODE v5.0 - Ultimate System Optimizer
#  Game Watcher | Live Monitor | Startup Manager | Before/After
# ============================================================
#  Usage:  TurboMode.ps1 [-Mode Menu|Game|Work|Clean|Watch|Monitor|Restore] [-Yes]
#          -Yes skips confirmations (for one-click shortcuts)
# ============================================================
param(
    [ValidateSet("Menu", "Game", "Work", "Clean", "Watch", "Monitor", "Restore")]
    [string]$Mode = "Menu",
    [switch]$Yes
)

# Self-elevate to admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $exe = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ($exe) {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$exe`" -Mode $Mode"
        if ($Yes) { $argList += " -Yes" }
        Start-Process powershell -Verb RunAs -ArgumentList $argList
    } else {
        Write-Host "  ERROR: Please run as Administrator!" -ForegroundColor Red
        Read-Host "  Press Enter to exit"
    }
    exit
}

$Host.UI.RawUI.WindowTitle = "TURBO MODE v5.0"

$TurboDir = "$env:USERPROFILE\.turbomode"
if (-not (Test-Path $TurboDir)) { New-Item -Path $TurboDir -ItemType Directory -Force | Out-Null }

# State lives in $TurboDir (NOT %TEMP%, which Clean-TempFiles wipes)
$StateServices  = "$TurboDir\state_services.txt"
$StatePowerPlan = "$TurboDir\state_powerplan.txt"
$LogFile        = "$TurboDir\turbomode.log"

function Write-Log {
    param([string]$Message)
    try { Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) } catch {}
}

# Only processes in the logged-in user's session are ever killed.
# Session 0 (Windows services, drivers, anti-cheat, antivirus) is never touched.
$MySessionId = (Get-Process -Id $PID).SessionId

# ---- SYSTEM-CRITICAL PROCESSES (NEVER KILL, even in user session) ----
$SystemCritical = @(
    "System", "Idle", "System Idle Process", "Secure System", "Registry",
    "MemCompression", "Memory Compression", "smss", "csrss",
    "wininit", "winlogon", "services", "lsass", "LsaIso", "svchost",
    "dwm", "fontdrvhost", "sihost", "taskhostw", "ctfmon", "conhost", "OpenConsole",
    "dllhost", "explorer", "SearchHost", "StartMenuExperienceHost",
    "TextInputHost", "ShellExperienceHost", "RuntimeBroker", "LockApp",
    "SecurityHealthSystray", "SecurityHealthService", "MsMpEng", "NisSrv",
    "MpDefenderCoreService", "SgrmBroker", "smartscreen",
    "WmiPrvSE", "unsecapp", "dasHost", "WUDFHost", "spoolsv", "SearchIndexer",
    "CompPkgSrv", "audiodg", "powershell", "pwsh", "WindowsTerminal", "cmd",
    "nvcontainer", "NVDisplay.Container", "atieclxx", "atiesrxx",
    "RtkAudUService64", "IntelCpHDCPSvc", "igfxCUIService", "igfxEM",
    "vgc", "vgtray", "TurboMode",
    "getscreen", "Getscreen", "FrameServer", "WindowsCamera"
)

# ---- GAME MODE KEEP LIST ----
$GameModeKeep = @(
    "RiotClientServices", "RiotClientUx", "RiotClientCrashHandler",
    "VALORANT-Win64-Shipping", "vgc", "vgtray",
    "getscreen", "Getscreen"
)

# ---- WORK MODE KEEP LIST ----
$WorkModeKeep = @(
    "Code", "devenv", "chrome", "msedge", "brave", "firefox",
    "OUTLOOK", "Teams", "ms-teams", "Slack", "discord",
    "OneDrive", "Dropbox", "GitHubDesktop",
    "node", "python", "docker", "WindowsTerminal",
    "Notion", "Obsidian",
    "getscreen", "Getscreen"
)

# ---- USER CONFIG ($TurboDir\config.json, created on first run) ----
$ConfigFile = "$TurboDir\config.json"
$DefaultConfig = [ordered]@{
    GameProcesses      = @("VALORANT-Win64-Shipping", "cs2", "FortniteClient-Win64-Shipping",
                           "r5apex", "GTA5", "RocketLeague", "League of Legends",
                           "Overwatch", "eldenring", "Cyberpunk2077", "bf2042")
    ExtraGameKeep      = @()
    ExtraWorkKeep      = @()
    WatcherIntervalSec = 15
    PingHost           = "1.1.1.1"
}
if (-not (Test-Path $ConfigFile)) {
    $DefaultConfig | ConvertTo-Json | Out-File $ConfigFile -Encoding UTF8 -Force
}
$Config = $DefaultConfig
try {
    $loaded = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    foreach ($key in @($DefaultConfig.Keys)) {
        if ($null -ne $loaded.$key) { $Config[$key] = $loaded.$key }
    }
} catch {
    Write-Host "  [!] config.json is invalid - using defaults" -ForegroundColor Yellow
}
$GameProcesses = @($Config.GameProcesses)
$GameModeKeep += $GameProcesses + @($Config.ExtraGameKeep)
$WorkModeKeep += @($Config.ExtraWorkKeep)

# ---- SMALL HELPERS ----
function Confirm-Action {
    param([string]$Prompt, [switch]$DefaultNo)
    if ($Yes) { return -not $DefaultNo }
    $hint = if ($DefaultNo) { "(y/N)" } else { "(Y/n)" }
    $ans = Read-Host "    $Prompt $hint"
    if ($DefaultNo) { return $ans -match '^(y|yes)$' }
    return $ans -notmatch '^(n|no)$'
}

function Test-QuitKey {
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Q' -or $k.Key -eq 'Escape') { return $true }
        }
    } catch {}
    return $false
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $sum = (Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    return [math]::Round(($sum / 1MB), 1)
}

function Get-Bar {
    param([double]$Pct, [int]$Width = 30)
    $Pct = [math]::Max(0, [math]::Min(100, $Pct))
    $n = [int][math]::Round($Pct / 100 * $Width)
    return ('#' * $n).PadRight($Width, '.')
}

function Get-QuickStats {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue).PercentProcessorTime
    $total = [math]::Round($os.TotalVisibleMemorySize / 1KB)
    $free = [math]::Round($os.FreePhysicalMemory / 1KB)
    return [PSCustomObject]@{
        TotalMB = $total; FreeMB = $free; UsedPct = [math]::Round((($total - $free) / $total) * 100, 1)
        CPU = [int]$cpu
    }
}

function Get-RunningGame {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $GameProcesses -contains $_.ProcessName } |
        Select-Object -First 1
}

function Set-GamePriority {
    param($Game)
    if (-not $Game) { return $false }
    try {
        $Game.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
        Write-Host "    >> $($Game.ProcessName) = HIGH priority!" -ForegroundColor Green
        Write-Log "Priority HIGH: $($Game.ProcessName)"
        return $true
    } catch {
        Write-Host "    ~ $($Game.ProcessName): anti-cheat blocked priority change (normal)" -ForegroundColor DarkGray
        return $false
    }
}

$PingSender = New-Object System.Net.NetworkInformation.Ping
function Get-PingMs {
    try {
        $r = $PingSender.Send([string]$Config.PingHost, 500)
        if ($r.Status -eq 'Success') { return [int]$r.RoundtripTime }
    } catch {}
    return -1
}

# NtSetTimerResolution: units of 100ns, 5000 = 0.5 ms. Windows drops the request
# automatically when this process exits, so it can never get "stuck".
function Set-TimerResolution {
    param([switch]$Enable)
    if (-not ("TurboTimer" -as [type])) {
        try {
            Add-Type -ErrorAction Stop -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class TurboTimer { [DllImport("ntdll.dll")] public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution); }'
        } catch { return $false }
    }
    $current = [uint32]0
    $status = [TurboTimer]::NtSetTimerResolution(5000, [bool]$Enable, [ref]$current)
    return ($status -eq 0)
}

$HistoryFile = "$TurboDir\history.csv"
function Save-SessionHistory {
    param($Row)
    try { $Row | Export-Csv -Path $HistoryFile -Append -NoTypeInformation -Force } catch {}
}

# Services to stop
$ServicesToStop = @(
    "WSearch", "SysMain", "DiagTrack", "dmwappushservice",
    "MapsBroker", "lfsvc", "SharedAccess", "Fax",
    "PrintNotify", "TabletInputService", "WMPNetworkSvc",
    "XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc"
)

# ============================================================
#  DEEP SYSTEM SNAPSHOT - Kernel level stats
# ============================================================
function Get-SystemSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

    # RAM details
    $totalRAM_MB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
    $freeRAM_MB = [math]::Round($os.FreePhysicalMemory / 1KB)
    $usedRAM_MB = $totalRAM_MB - $freeRAM_MB
    $ramPct = [math]::Round(($usedRAM_MB / $totalRAM_MB) * 100, 1)

    # Virtual memory / Page file
    $totalVirtual_MB = [math]::Round($os.TotalVirtualMemorySize / 1KB)
    $freeVirtual_MB = [math]::Round($os.FreeVirtualMemory / 1KB)

    # Commit charge (actual memory pressure)
    $commitTotal = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue)
    $commitMB = 0
    $cacheMB = 0
    $pageFaults = 0
    if ($commitTotal) {
        $commitMB = [math]::Round($commitTotal.CommittedBytes / 1MB)
        $cacheMB = [math]::Round($commitTotal.CacheBytes / 1MB)
        $pageFaults = $commitTotal.PageFaultsPersec
    }

    # CPU usage
    $cpuLoad = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue)
    $cpuPct = 0
    if ($cpuLoad) { $cpuPct = $cpuLoad.PercentProcessorTime }

    # Disk
    $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $diskTotalGB = [math]::Round($disk.Size / 1GB, 2)
    $diskUsedGB = [math]::Round($diskTotalGB - $diskFreeGB, 2)

    # Process count
    $allProcs = Get-Process
    $procCount = $allProcs.Count
    # .Threads is a collection, so count it - Measure-Object -Property Threads errors on every process
    $threadCount = ($allProcs | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
    $handleCount = 0
    try {
        $handleCount = ($allProcs | Measure-Object -Property HandleCount -Sum).Sum
    } catch {}

    # Temp folder sizes
    $tempSizes = Get-TempFolderSizes

    # Uptime
    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    return [PSCustomObject]@{
        TotalRAM_MB    = $totalRAM_MB
        FreeRAM_MB     = $freeRAM_MB
        UsedRAM_MB     = $usedRAM_MB
        RAM_Pct        = $ramPct
        TotalVirt_MB   = $totalVirtual_MB
        FreeVirt_MB    = $freeVirtual_MB
        CommitMB       = $commitMB
        CacheMB        = $cacheMB
        PageFaults     = $pageFaults
        CPU_Pct        = $cpuPct
        DiskFreeGB     = $diskFreeGB
        DiskTotalGB    = $diskTotalGB
        DiskUsedGB     = $diskUsedGB
        ProcessCount   = $procCount
        ThreadCount    = $threadCount
        HandleCount    = $handleCount
        TempSizesMB    = $tempSizes
        Uptime         = $uptimeStr
    }
}

function Get-TempFolderSizes {
    $folders = @{
        "User Temp"     = $env:TEMP
        "Windows Temp"  = "$env:SystemRoot\Temp"
        "Thumbnails"    = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        "Windows Update"= "$env:SystemRoot\SoftwareDistribution\Download"
        "Crash Dumps"   = "$env:LOCALAPPDATA\CrashDumps"
        "Edge Cache"    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
        "Chrome Cache"  = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    }

    $result = @{}
    foreach ($entry in $folders.GetEnumerator()) {
        $size = 0
        if (Test-Path $entry.Value) {
            try {
                $size = [math]::Round((Get-ChildItem -Path $entry.Value -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
            } catch { $size = 0 }
        }
        $result[$entry.Key] = @{ Path = $entry.Value; SizeMB = $size }
    }
    return $result
}

# ============================================================
#  DISPLAY SNAPSHOT
# ============================================================
function Show-Snapshot {
    param([PSCustomObject]$Snap, [string]$Label)

    $ramColor = "Green"
    if ($Snap.RAM_Pct -gt 60) { $ramColor = "Yellow" }
    if ($Snap.RAM_Pct -gt 80) { $ramColor = "Red" }

    Write-Host "  $Label" -ForegroundColor Cyan
    Write-Host "  $('=' * 55)" -ForegroundColor DarkGray

    Write-Host -NoNewline "    RAM Used:      "
    Write-Host "$($Snap.UsedRAM_MB) MB / $($Snap.TotalRAM_MB) MB ($($Snap.RAM_Pct)%)" -ForegroundColor $ramColor

    Write-Host "    RAM Free:      $($Snap.FreeRAM_MB) MB"
    Write-Host "    Commit:        $($Snap.CommitMB) MB"
    Write-Host "    Cache:         $($Snap.CacheMB) MB"
    Write-Host "    Page Faults/s: $($Snap.PageFaults)"
    Write-Host ""
    Write-Host "    CPU Usage:     $($Snap.CPU_Pct)%"
    Write-Host "    Processes:     $($Snap.ProcessCount)"
    Write-Host "    Threads:       $($Snap.ThreadCount)"
    Write-Host "    Handles:       $($Snap.HandleCount)"
    Write-Host ""
    Write-Host "    Disk C: Free:  $($Snap.DiskFreeGB) GB / $($Snap.DiskTotalGB) GB"
    Write-Host "    Uptime:        $($Snap.Uptime)"
    Write-Host ""

    if ($Snap.TempSizesMB -and $Snap.TempSizesMB.Count -gt 0) {
        Write-Host "    TEMP/JUNK FOLDERS:" -ForegroundColor DarkGray
        $totalTemp = 0
        foreach ($entry in $Snap.TempSizesMB.GetEnumerator()) {
            $sz = $entry.Value.SizeMB
            $totalTemp += $sz
            if ($sz -gt 0) {
                $szColor = "Green"
                if ($sz -gt 100) { $szColor = "Yellow" }
                if ($sz -gt 500) { $szColor = "Red" }
                Write-Host -NoNewline ("      {0,-20}" -f $entry.Key)
                Write-Host ("{0,8} MB" -f $sz) -ForegroundColor $szColor
            }
        }
        Write-Host "      $('-' * 30)" -ForegroundColor DarkGray
        Write-Host -NoNewline "      TOTAL JUNK:           "
        Write-Host ("{0} MB" -f [math]::Round($totalTemp)) -ForegroundColor Red
        Write-Host ""
    }
}

# ============================================================
#  SHOW BEFORE/AFTER COMPARISON
# ============================================================
function Show-Comparison {
    param([PSCustomObject]$Before, [PSCustomObject]$After)

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Yellow
    Write-Host "  |       BEFORE  vs  AFTER  COMPARISON      |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Yellow
    Write-Host ""

    $ramFreed = $After.FreeRAM_MB - $Before.FreeRAM_MB
    $procsKilled = $Before.ProcessCount - $After.ProcessCount
    $threadsFreed = $Before.ThreadCount - $After.ThreadCount
    $handlesFreed = $Before.HandleCount - $After.HandleCount
    $diskFreed = [math]::Round($After.DiskFreeGB - $Before.DiskFreeGB, 2)
    $cpuDrop = $Before.CPU_Pct - $After.CPU_Pct

    Write-Host ("  {0,-25} {1,12} {2,12} {3,12}" -f "METRIC", "BEFORE", "AFTER", "CHANGE") -ForegroundColor White
    Write-Host "  $('-' * 65)" -ForegroundColor DarkGray

    # RAM
    $ramSign = if ($ramFreed -ge 0) { "+" } else { "" }
    $ramColor = if ($ramFreed -ge 0) { "Green" } else { "Red" }
    Write-Host -NoNewline ("  {0,-25} {1,9} MB {2,9} MB " -f "RAM Free", $Before.FreeRAM_MB, $After.FreeRAM_MB)
    Write-Host ("{0}{1} MB" -f $ramSign, $ramFreed) -ForegroundColor $ramColor

    Write-Host -NoNewline ("  {0,-25} {1,9} MB {2,9} MB " -f "RAM Used", $Before.UsedRAM_MB, $After.UsedRAM_MB)
    $usedDiff = $Before.UsedRAM_MB - $After.UsedRAM_MB
    $usedColor = if ($usedDiff -ge 0) { "Green" } else { "Red" }
    Write-Host ("-{0} MB" -f $usedDiff) -ForegroundColor $usedColor

    # CPU
    Write-Host -NoNewline ("  {0,-25} {1,10}% {2,10}% " -f "CPU Usage", $Before.CPU_Pct, $After.CPU_Pct)
    $cpuColor = if ($cpuDrop -ge 0) { "Green" } else { "Red" }
    $cpuSign = if ($cpuDrop -ge 0) { "-" } else { "+" }
    Write-Host ("{0}{1}%" -f $cpuSign, [math]::Abs($cpuDrop)) -ForegroundColor $cpuColor

    # Processes
    Write-Host -NoNewline ("  {0,-25} {1,12} {2,12} " -f "Processes", $Before.ProcessCount, $After.ProcessCount)
    Write-Host ("-{0}" -f $procsKilled) -ForegroundColor Green

    # Threads
    Write-Host -NoNewline ("  {0,-25} {1,12} {2,12} " -f "Threads", $Before.ThreadCount, $After.ThreadCount)
    Write-Host ("-{0}" -f $threadsFreed) -ForegroundColor Green

    # Handles
    Write-Host -NoNewline ("  {0,-25} {1,12} {2,12} " -f "Handles", $Before.HandleCount, $After.HandleCount)
    Write-Host ("-{0}" -f $handlesFreed) -ForegroundColor Green

    # Disk
    Write-Host -NoNewline ("  {0,-25} {1,9} GB {2,9} GB " -f "Disk Free (C:)", $Before.DiskFreeGB, $After.DiskFreeGB)
    $diskColor = if ($diskFreed -ge 0) { "Green" } else { "Red" }
    Write-Host ("+{0} GB" -f $diskFreed) -ForegroundColor $diskColor

    Write-Host ""
    Write-Host "  $('=' * 65)" -ForegroundColor DarkGray

    # Summary score
    $score = 0
    if ($ramFreed -gt 0) { $score += [math]::Min($ramFreed / 100, 30) }
    if ($procsKilled -gt 0) { $score += [math]::Min($procsKilled, 20) }
    if ($diskFreed -gt 0) { $score += [math]::Min($diskFreed * 5, 20) }
    if ($cpuDrop -gt 0) { $score += [math]::Min($cpuDrop / 2, 15) }
    if ($threadsFreed -gt 0) { $score += [math]::Min($threadsFreed / 50, 15) }
    $score = [math]::Min([math]::Round($score), 100)

    $scoreColor = "Red"
    $scoreLabel = "MINIMAL"
    if ($score -gt 20) { $scoreColor = "Yellow"; $scoreLabel = "MODERATE" }
    if ($score -gt 50) { $scoreColor = "Green"; $scoreLabel = "GOOD" }
    if ($score -gt 75) { $scoreColor = "Cyan"; $scoreLabel = "EXCELLENT" }

    Write-Host ""
    Write-Host -NoNewline "  OPTIMIZATION SCORE: "
    Write-Host "${score}/100 - ${scoreLabel}" -ForegroundColor $scoreColor
    Write-Host ""

    if ($ramFreed -gt 500) {
        Write-Host "  >> Freed over 500MB RAM - big improvement!" -ForegroundColor Green
    }
    if ($procsKilled -gt 50) {
        Write-Host "  >> Killed $procsKilled processes - system is much cleaner!" -ForegroundColor Green
    }
    if ($diskFreed -gt 1) {
        Write-Host "  >> Recovered ${diskFreed}GB disk space from junk files!" -ForegroundColor Green
    }
    Write-Host ""
}

# ============================================================
#  BANNER
# ============================================================
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +=========================================================+" -ForegroundColor Red
    Write-Host "  |                                                         |" -ForegroundColor Red
    Write-Host "  |        >>> T U R B O   M O D E   v 5 . 0 <<<            |" -ForegroundColor Red
    Write-Host "  |        Ultimate System Optimizer                        |" -ForegroundColor Red
    Write-Host "  |                                                         |" -ForegroundColor Red
    Write-Host "  +=========================================================+" -ForegroundColor Red
    Write-Host ""
}

# ============================================================
#  CLEAN TEMP/JUNK FILES
# ============================================================
function Clean-TempFiles {
    Write-Host "  [CLEAN] ERASING JUNK FILES..." -ForegroundColor Yellow
    Write-Host "  -----------------------------" -ForegroundColor DarkGray

    $totalCleaned = 0

    # Prefetch, Recent, Icon/Font cache were removed on purpose: deleting them
    # makes Windows rebuild them and apps start SLOWER afterwards.
    $targets = @(
        @{ Name = "User Temp";       Path = $env:TEMP },
        @{ Name = "Windows Temp";    Path = "$env:SystemRoot\Temp" },
        @{ Name = "Thumbnails";      Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" },
        @{ Name = "Win Update DL";   Path = "$env:SystemRoot\SoftwareDistribution\Download" },
        @{ Name = "Crash Dumps";     Path = "$env:LOCALAPPDATA\CrashDumps" },
        @{ Name = "Edge Cache";      Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" },
        @{ Name = "Chrome Cache";    Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" },
        @{ Name = "Brave Cache";     Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache" },
        @{ Name = "Logs";            Path = "$env:SystemRoot\Logs\CBS\*.log" },
        @{ Name = "Error Reports";   Path = "$env:LOCALAPPDATA\Microsoft\Windows\WER" },
        @{ Name = "D3D Shader Cache";Path = "$env:LOCALAPPDATA\D3DSCache" }
    )

    foreach ($t in $targets) {
        if (Test-Path $t.Path) {
            try {
                $sizeBefore = 0
                if ($t.Path -match '\*') {
                    $files = Get-Item $t.Path -Force -ErrorAction SilentlyContinue
                    if ($files) {
                        $sizeBefore = ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        $files | Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    $items = Get-ChildItem -Path $t.Path -Recurse -Force -ErrorAction SilentlyContinue
                    if ($items) {
                        $sizeBefore = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                        $items | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                    }
                }
                $cleanedMB = [math]::Round($sizeBefore / 1MB, 1)
                $totalCleaned += $cleanedMB
                if ($cleanedMB -gt 0) {
                    Write-Host "    [DEL] $($t.Name): ${cleanedMB} MB cleared" -ForegroundColor DarkYellow
                }
            } catch {}
        }
    }

    # Recycle Bin is permanent deletion - always ask
    # -Yes never empties the bin; it must be an explicit choice
    if (Confirm-Action "Also empty the Recycle Bin?" -DefaultNo) {
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
            Write-Host "    [DEL] Recycle Bin emptied" -ForegroundColor DarkYellow
        } catch {}
    }

    # Delivery Optimization cache
    $doPath = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
    if (Test-Path $doPath) {
        try {
            Remove-Item "$doPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "    [DEL] Delivery Optimization cache cleared" -ForegroundColor DarkYellow
        } catch {}
    }

    # Also clean Windows Disk Cleanup silently
    try {
        # Set all cleanup flags
        $cleanupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
        Get-ChildItem $cleanupKey -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name "StateFlags0099" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        }
        # Run cleanup
        Start-Process cleanmgr -ArgumentList "/sagerun:99" -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Host "    [DEL] Windows Disk Cleanup triggered" -ForegroundColor DarkYellow
    } catch {}

    Write-Host ""
    Write-Host "    >> Total cleaned: ~${totalCleaned} MB" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  KERNEL-LEVEL PROCESS LIST
# ============================================================
function Get-KernelProcessList {
    # Use WMI for kernel-level process info (parent PID, command line, priority)
    # Protect this script and every process above it (TurboMode.exe, console host...)
    $protectedPids = @($PID)
    $cursor = $PID
    for ($i = 0; $i -lt 6; $i++) {
        $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$cursor" -ErrorAction SilentlyContinue).ParentProcessId
        if (-not $parent) { break }
        $protectedPids += $parent
        $cursor = $parent
    }

    $wmiProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.SessionId -eq $MySessionId -and
            $SystemCritical -notcontains $_.Name.Replace(".exe", "") -and
            $protectedPids -notcontains $_.ProcessId
        }

    $grouped = $wmiProcs | Group-Object Name | ForEach-Object {
        $totalMem = 0
        $pids = @()
        foreach ($p in $_.Group) {
            $totalMem += $p.WorkingSetSize
            $pids += $p.ProcessId
        }
        $procName = $_.Name.Replace(".exe", "")

        [PSCustomObject]@{
            Name       = $procName
            FullName   = $_.Name
            Count      = $_.Count
            MemoryMB   = [math]::Round($totalMem / 1MB)
            PIDs       = $pids
            Category   = Get-ProcessCategory $procName
            CommandLine= $_.Group[0].CommandLine
            ParentPID  = $_.Group[0].ParentProcessId
        }
    } | Sort-Object MemoryMB -Descending

    return $grouped
}

function Get-ProcessCategory {
    param([string]$Name)
    $categories = @{
        "Browser"       = @("chrome", "firefox", "msedge", "opera", "brave", "iexplore", "GoogleUpdate", "MicrosoftEdgeUpdate")
        "Communication" = @("Teams", "ms-teams", "Slack", "Skype", "SkypeApp", "Telegram", "WhatsApp", "Zoom", "discord", "Discord", "DiscordPTB", "DiscordCanary")
        "Office"        = @("WINWORD", "EXCEL", "POWERPNT", "OUTLOOK", "ONENOTE", "MSACCESS")
        "Cloud/Sync"    = @("OneDrive", "Dropbox", "GoogleDriveSync", "iCloudServices")
        "Media"         = @("Spotify", "SpotifyWebHelper", "iTunes", "vlc", "wmplayer")
        "Adobe"         = @("AdobeIPCBroker", "AdobeUpdateService", "CCXProcess", "CCLibrary", "AcroRd32", "Acrobat", "Photoshop")
        "Dev Tools"     = @("Code", "devenv", "idea64", "phpstorm64", "webstorm64", "pycharm64", "node", "python", "java", "docker", "GitHubDesktop")
        "Gaming"        = @("RiotClientServices", "RiotClientUx", "RiotClientCrashHandler", "VALORANT-Win64-Shipping", "EpicGamesLauncher", "EpicWebHelper", "Steam", "steamwebhelper", "SteamService", "Origin", "OriginWebHelperService", "GameBar", "GameBarPresenceWriter")
        "System Bloat"  = @("YourPhone", "CalculatorApp", "Microsoft.Photos", "HxTsr", "HxOutlook", "HxCalendarAppImm", "widgets", "WidgetService", "TabTip", "TabTip32", "NahimicService", "NahimicSvc64")
        "Recording"     = @("ShareX", "LightShot", "Snagit", "OBS64", "obs64", "ScreenClip")
    }
    foreach ($cat in $categories.GetEnumerator()) {
        if ($cat.Value -contains $Name) { return $cat.Key }
    }
    return "Other"
}

# ============================================================
#  DISPLAY PROCESS TABLE
# ============================================================
function Show-ProcessTable {
    param([array]$Processes, [array]$Selected)

    Write-Host ("  {0,4} {1,3} {2,-30} {3,5} {4,8} {5,-13}" -f "#", "SEL", "PROCESS", "QTY", "RAM MB", "CATEGORY") -ForegroundColor White
    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray

    for ($i = 0; $i -lt $Processes.Count; $i++) {
        $p = $Processes[$i]
        $num = $i + 1
        $sel = if ($Selected -contains $i) { "[X]" } else { "[ ]" }
        $selColor = if ($Selected -contains $i) { "Red" } else { "DarkGray" }

        $memColor = "Green"
        if ($p.MemoryMB -gt 100) { $memColor = "Yellow" }
        if ($p.MemoryMB -gt 300) { $memColor = "Red" }

        $catColor = switch ($p.Category) {
            "Browser"       { "Cyan" }
            "Communication" { "Magenta" }
            "Gaming"        { "Red" }
            "Dev Tools"     { "Green" }
            "Media"         { "Yellow" }
            "System Bloat"  { "DarkGray" }
            default         { "White" }
        }

        $nameStr = $p.Name
        if ($nameStr.Length -gt 30) { $nameStr = $nameStr.Substring(0, 27) + "..." }
        $countStr = if ($p.Count -gt 1) { "$($p.Count)x" } else { "1" }

        Write-Host -NoNewline ("  {0,4} " -f $num)
        Write-Host -NoNewline $sel -ForegroundColor $selColor
        Write-Host -NoNewline (" {0,-30} {1,5} " -f $nameStr, $countStr)
        Write-Host -NoNewline ("{0,6}" -f $p.MemoryMB) -ForegroundColor $memColor
        Write-Host -NoNewline "   "
        Write-Host $p.Category -ForegroundColor $catColor
    }

    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
    $totalMem = ($Processes | Where-Object { $Selected -contains $Processes.IndexOf($_) } | Measure-Object MemoryMB -Sum).Sum
    if ($null -eq $totalMem) { $totalMem = 0 }
    Write-Host "  Selected: $($Selected.Count) | Will free: ~${totalMem} MB RAM" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================
#  INTERACTIVE PROCESS SELECTOR
# ============================================================
function Select-Processes {
    param([array]$Processes, [array]$PreSelected = @())

    $selected = [System.Collections.ArrayList]@($PreSelected)

    while ($true) {
        Show-Banner
        Write-Host "  CUSTOM MODE - SELECT PROCESSES TO KILL" -ForegroundColor Magenta
        Write-Host "  Mark [X] = will be KILLED" -ForegroundColor DarkGray
        Write-Host ""

        Show-ProcessTable -Processes $Processes -Selected $selected

        Write-Host "  COMMANDS:" -ForegroundColor White
        Write-Host "    <number>     Toggle (e.g. 3)        all       Select all" -ForegroundColor DarkGray
        Write-Host "    <range>      Range (e.g. 3-7)       none      Deselect all" -ForegroundColor DarkGray
        Write-Host "    big          All >100MB RAM          cat <x>   By category" -ForegroundColor DarkGray
        Write-Host "    save <name>  Save profile            load <x>  Load profile" -ForegroundColor DarkGray
        Write-Host "    profiles     List profiles           GO        EXECUTE KILL" -ForegroundColor DarkGray
        Write-Host "    back         Return to menu" -ForegroundColor DarkGray
        Write-Host ""
        $userInput = Read-Host "  >"

        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

        switch -Regex ($userInput.Trim().ToLower()) {
            "^go$" { return $selected.ToArray() }
            "^back$" { return $null }
            "^all$" {
                $selected.Clear()
                for ($i = 0; $i -lt $Processes.Count; $i++) { $selected.Add($i) | Out-Null }
            }
            "^none$" { $selected.Clear() }
            "^big$" {
                for ($i = 0; $i -lt $Processes.Count; $i++) {
                    if ($Processes[$i].MemoryMB -gt 100 -and $selected -notcontains $i) {
                        $selected.Add($i) | Out-Null
                    }
                }
            }
            "^cat (.+)$" {
                $catName = $Matches[1].Trim()
                for ($i = 0; $i -lt $Processes.Count; $i++) {
                    if ($Processes[$i].Category -match $catName -and $selected -notcontains $i) {
                        $selected.Add($i) | Out-Null
                    }
                }
            }
            "^save (.+)$" {
                $profileName = $Matches[1].Trim()
                $profileData = @()
                foreach ($idx in $selected) { $profileData += $Processes[$idx].Name }
                $profileData | Out-File "$TurboDir\profile_${profileName}.txt" -Force
                Write-Host "    >> Profile '$profileName' saved!" -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            "^load (.+)$" {
                $profileName = $Matches[1].Trim()
                $profilePath = "$TurboDir\profile_${profileName}.txt"
                if (Test-Path $profilePath) {
                    $profileProcs = Get-Content $profilePath
                    $selected.Clear()
                    for ($i = 0; $i -lt $Processes.Count; $i++) {
                        if ($profileProcs -contains $Processes[$i].Name) { $selected.Add($i) | Out-Null }
                    }
                    Write-Host "    >> Loaded!" -ForegroundColor Green
                } else { Write-Host "    >> Not found!" -ForegroundColor Red }
                Start-Sleep -Seconds 1
            }
            "^profiles$" {
                $pfs = Get-ChildItem "$TurboDir\profile_*.txt" -ErrorAction SilentlyContinue
                if ($pfs) {
                    foreach ($pf in $pfs) {
                        $n = $pf.BaseName -replace "^profile_", ""
                        Write-Host "      - $n" -ForegroundColor Cyan
                    }
                } else { Write-Host "    No profiles." -ForegroundColor DarkGray }
                Read-Host "    Enter to continue"
            }
            "^(\d+)-(\d+)$" {
                $s = [int]$Matches[1] - 1; $e = [int]$Matches[2] - 1
                for ($i = $s; $i -le $e -and $i -lt $Processes.Count; $i++) {
                    if ($i -ge 0) {
                        if ($selected -contains $i) { $selected.Remove($i) }
                        else { $selected.Add($i) | Out-Null }
                    }
                }
            }
            "^(\d+)$" {
                $idx = [int]$Matches[1] - 1
                if ($idx -ge 0 -and $idx -lt $Processes.Count) {
                    if ($selected -contains $idx) { $selected.Remove($idx) }
                    else { $selected.Add($idx) | Out-Null }
                }
            }
        }
    }
}

# ============================================================
#  KILL PROCESSES
# ============================================================
function Kill-SelectedProcesses {
    param([array]$Processes, [array]$Indices)

    # NOTE: never name the loop variable $pid - $PID is read-only in PowerShell
    $killed = 0
    $failed = 0
    foreach ($idx in $Indices) {
        $p = $Processes[$idx]
        $ok = 0
        foreach ($procId in $p.PIDs) {
            try {
                Stop-Process -Id $procId -Force -ErrorAction Stop
                $ok++
            } catch {
                # Already exited counts as success; access denied does not
                if (Get-Process -Id $procId -ErrorAction SilentlyContinue) { $failed++ } else { $ok++ }
            }
        }
        $killed += $ok
        if ($ok -gt 0) {
            Write-Host "    X $($p.Name) ($ok proc, $($p.MemoryMB) MB)" -ForegroundColor Red
            Write-Log "Killed $($p.Name) x$ok ($($p.MemoryMB) MB)"
        } else {
            Write-Host "    ~ $($p.Name) (protected / access denied)" -ForegroundColor DarkGray
        }
    }
    Write-Host "    >> Killed $killed processes" -ForegroundColor Green
    if ($failed -gt 0) { Write-Host "    >> $failed could not be stopped (protected)" -ForegroundColor DarkGray }
    Write-Host ""
}

# ============================================================
#  SYSTEM OPTIMIZATIONS
# ============================================================
function Run-SystemOptimizations {
    # Stop services
    Write-Host "  [OPT] STOPPING JUNK SERVICES..." -ForegroundColor Yellow
    $stoppedServices = @()
    foreach ($svc in $ServicesToStop) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            try {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                $stoppedServices += $svc
                Write-Host "    [STOP] $svc" -ForegroundColor DarkYellow
            } catch {}
        }
    }
    # Merge with services already stopped by a previous run so Restore gets them all
    if (Test-Path $StateServices) { $stoppedServices += Get-Content $StateServices }
    $stoppedServices | Where-Object { $_ } | Sort-Object -Unique | Out-File $StateServices -Force
    Write-Host ""

    # Power plan - only remember the ORIGINAL plan, not one Turbo Mode already set
    Write-Host "  [OPT] HIGH PERFORMANCE POWER..." -ForegroundColor Yellow
    if (-not (Test-Path $StatePowerPlan)) {
        powercfg /getactivescheme | Out-File $StatePowerPlan -Force
    }
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    $ultimate = powercfg /list | Select-String "e9a42b02-d5df-448d-aa00-03f14749eb61"
    if ($ultimate) {
        powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61
        Write-Host "    >> Ultimate Performance!" -ForegroundColor Cyan
    } else {
        Write-Host "    >> High Performance" -ForegroundColor Green
    }
    Write-Host ""

    # Free RAM - kernel level
    Write-Host "  [OPT] DEEP RAM CLEANUP..." -ForegroundColor Yellow
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()

    $csharpCode = 'using System; using System.Runtime.InteropServices; public class MemCleaner { [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess); [DllImport("kernel32.dll")] public static extern bool SetProcessWorkingSetSize(IntPtr proc, IntPtr min, IntPtr max); }'
    if (-not ("MemCleaner" -as [type])) {
        try { Add-Type -TypeDefinition $csharpCode -ErrorAction Stop } catch {}
    }

    $cleaned = 0
    Get-Process | Where-Object { $SystemCritical -notcontains $_.ProcessName } | ForEach-Object {
        try {
            if ([MemCleaner]::EmptyWorkingSet($_.Handle)) { $cleaned++ }
        } catch {}
    }
    Write-Host "    >> Cleaned working sets of $cleaned processes" -ForegroundColor Green

    # Try Standby List Purge
    $dllPath = Join-Path $PSScriptRoot "KernelMemOptimizer.dll"
    if (Test-Path $dllPath) {
        try {
            Add-Type -Path $dllPath -ErrorAction SilentlyContinue
            [KernelMemOptimizer]::PurgeStandby()
            Write-Host "    >> Standby list & cache memory purged" -ForegroundColor Cyan
        } catch {}
    }
    Write-Host ""

    # Network
    Write-Host "  [OPT] NETWORK..." -ForegroundColor Yellow
    ipconfig /flushdns 2>$null | Out-Null
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    } catch {}
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" -Name "NonBestEffortLimit" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    } catch {}
    Write-Host "    >> DNS flushed, throttling disabled" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  GAME MODE
# ============================================================
function Start-GameMode {
    Show-Banner
    Write-Host "  Taking BEFORE snapshot..." -ForegroundColor DarkGray
    $before = Get-SystemSnapshot
    Show-Snapshot -Snap $before -Label "BEFORE - CURRENT STATE"
    Write-Host ""

    Write-Host "  >>> GAME MODE ACTIVATED <<<" -ForegroundColor Red
    Write-Host "  =============================" -ForegroundColor Red
    Write-Host ""

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host "  [1/4] KILLING BACKGROUND APPS..." -ForegroundColor Yellow
    $procs = @(Get-KernelProcessList)
    $toKill = @()
    for ($i = 0; $i -lt $procs.Count; $i++) {
        if ($GameModeKeep -notcontains $procs[$i].Name) { $toKill += $i }
    }
    $killMB = ($toKill | ForEach-Object { $procs[$_].MemoryMB } | Measure-Object -Sum).Sum
    Write-Host ("    Will close {0} apps (~{1} MB): {2}" -f $toKill.Count, $killMB, (($toKill | ForEach-Object { $procs[$_].Name }) -join ", ")) -ForegroundColor DarkGray
    if (-not (Confirm-Action "Save your work! Continue?")) { Write-Host "  Cancelled." -ForegroundColor DarkGray; return }
    Kill-SelectedProcesses -Processes $procs -Indices $toKill

    Write-Host "  [2/4] CLEANING TEMP/JUNK..." -ForegroundColor Yellow
    Clean-TempFiles

    Write-Host "  [3/4] SYSTEM OPTIMIZATIONS..." -ForegroundColor Yellow
    Run-SystemOptimizations

    Write-Host "  [4/4] GAME PRIORITY..." -ForegroundColor Yellow
    $game = Get-RunningGame
    if ($game) {
        Set-GamePriority $game | Out-Null
    } else {
        Write-Host "    >> Launch your game now! (tip: GAME WATCHER boosts it automatically)" -ForegroundColor Cyan
    }

    $sw.Stop()
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ""

    Write-Host "  Taking AFTER snapshot..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
    $after = Get-SystemSnapshot

    Show-Comparison -Before $before -After $after

    Write-Host "  GAME MODE ACTIVE! (${elapsed}s)" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  WORK MODE
# ============================================================
function Start-WorkMode {
    Show-Banner
    Write-Host "  Taking BEFORE snapshot..." -ForegroundColor DarkGray
    $before = Get-SystemSnapshot
    Show-Snapshot -Snap $before -Label "BEFORE - CURRENT STATE"
    Write-Host ""

    Write-Host "  >>> WORK MODE ACTIVATED <<<" -ForegroundColor Green
    Write-Host "  =============================" -ForegroundColor Green
    Write-Host ""

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host "  [1/3] KILLING BLOAT..." -ForegroundColor Yellow
    $procs = Get-KernelProcessList
    $toKill = @()
    for ($i = 0; $i -lt $procs.Count; $i++) {
        $p = $procs[$i]
        if ($p.Category -in @("Gaming", "Media", "System Bloat") -and $WorkModeKeep -notcontains $p.Name) {
            $toKill += $i
        }
    }
    Kill-SelectedProcesses -Processes $procs -Indices $toKill

    Write-Host "  [2/3] CLEANING TEMP/JUNK..." -ForegroundColor Yellow
    Clean-TempFiles

    Write-Host "  [3/3] SYSTEM OPTIMIZATIONS..." -ForegroundColor Yellow
    Run-SystemOptimizations

    $sw.Stop()
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ""

    Write-Host "  Taking AFTER snapshot..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
    $after = Get-SystemSnapshot

    Show-Comparison -Before $before -After $after

    Write-Host "  WORK MODE ACTIVE! (${elapsed}s)" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  CUSTOM MODE
# ============================================================
function Start-CustomMode {
    $procs = Get-KernelProcessList
    if ($procs.Count -eq 0) {
        Write-Host "  No killable processes!" -ForegroundColor DarkGray
        return
    }

    $selected = Select-Processes -Processes $procs
    if ($null -eq $selected -or $selected.Count -eq 0) {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
        return
    }

    Show-Banner
    Write-Host "  Taking BEFORE snapshot..." -ForegroundColor DarkGray
    $before = Get-SystemSnapshot

    Write-Host "  >>> CUSTOM MODE <<<" -ForegroundColor Magenta
    Write-Host ""

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host "  [1/3] KILLING SELECTED..." -ForegroundColor Yellow
    Kill-SelectedProcesses -Processes $procs -Indices $selected

    Write-Host "  [2/3] CLEANING TEMP/JUNK..." -ForegroundColor Yellow
    Clean-TempFiles

    Write-Host "  [3/3] OPTIMIZATIONS..." -ForegroundColor Yellow
    Run-SystemOptimizations

    $sw.Stop()
    $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    Write-Host "  Taking AFTER snapshot..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
    $after = Get-SystemSnapshot

    Show-Comparison -Before $before -After $after

    Write-Host "  CUSTOM MODE DONE! (${elapsed}s)" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  DEEP CLEAN ONLY (no process killing)
# ============================================================
function Start-DeepClean {
    Show-Banner
    Write-Host "  Taking BEFORE snapshot..." -ForegroundColor DarkGray
    $before = Get-SystemSnapshot
    Show-Snapshot -Snap $before -Label "BEFORE - CURRENT STATE"
    Write-Host ""

    Write-Host "  >>> DEEP CLEAN MODE <<<" -ForegroundColor Yellow
    Write-Host "  ========================" -ForegroundColor Yellow
    Write-Host ""

    Clean-TempFiles
    Clean-DevCaches
    Run-SystemOptimizations

    Write-Host "  Taking AFTER snapshot..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
    $after = Get-SystemSnapshot

    Show-Comparison -Before $before -After $after
    Write-Host ""
}

# ============================================================
#  DEVELOPER CACHES (safe to delete - tools re-download on demand)
# ============================================================
function Clean-DevCaches {
    $caches = @(
        @{ Name = "npm cache";   Path = "$env:LOCALAPPDATA\npm-cache" },
        @{ Name = "pip cache";   Path = "$env:LOCALAPPDATA\pip\Cache" },
        @{ Name = "Yarn cache";  Path = "$env:LOCALAPPDATA\Yarn\Cache" },
        @{ Name = "pnpm store";  Path = "$env:LOCALAPPDATA\pnpm\store" },
        @{ Name = "NuGet http";  Path = "$env:LOCALAPPDATA\NuGet\v3-cache" },
        @{ Name = "Go build";    Path = "$env:LOCALAPPDATA\go-build" }
    )
    $found = @()
    foreach ($c in $caches) {
        $mb = Get-FolderSizeMB $c.Path
        if ($mb -gt 1) { $found += [PSCustomObject]@{ Name = $c.Name; Path = $c.Path; MB = $mb } }
    }
    if ($found.Count -eq 0) { return }

    $total = [math]::Round(($found | Measure-Object MB -Sum).Sum)
    Write-Host "  [DEV] DEVELOPER CACHES FOUND (~$total MB):" -ForegroundColor Yellow
    foreach ($f in $found) { Write-Host ("    {0,-12} {1,8} MB" -f $f.Name, $f.MB) -ForegroundColor DarkGray }
    if (-not (Confirm-Action "Clear these caches? (packages re-download when needed)")) { Write-Host ""; return }

    foreach ($f in $found) {
        Get-ChildItem -Path $f.Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [DEL] $($f.Name): $($f.MB) MB" -ForegroundColor DarkYellow
    }
    Write-Log "Dev caches cleared: ~$total MB"
    Write-Host ""
}

# ============================================================
#  GAME WATCHER - auto boost when a game starts, auto restore when it exits
# ============================================================
function Start-GameWatcher {
    Show-Banner
    Write-Host "  >>> GAME WATCHER <<<" -ForegroundColor Red
    Write-Host "  Watching for: $($GameProcesses -join ', ')" -ForegroundColor DarkGray
    Write-Host "  (edit the list in $ConfigFile)" -ForegroundColor DarkGray
    Write-Host "  Press Q to stop watching." -ForegroundColor DarkGray
    Write-Host ""

    $game = $null
    while (-not $game) {
        if (Test-QuitKey) { Write-Host "`n  Watcher stopped." -ForegroundColor DarkGray; return }
        $game = Get-RunningGame
        if (-not $game) {
            Write-Host -NoNewline ("`r  Waiting for a game to launch...  {0}   " -f (Get-Date -Format "HH:mm:ss")) -ForegroundColor Cyan
            Start-Sleep -Seconds 2
        }
    }

    Write-Host ""
    Write-Host ""
    Write-Host "  >> DETECTED: $($game.ProcessName) - BOOSTING!" -ForegroundColor Green
    Write-Log "Watcher detected $($game.ProcessName)"
    $before = Get-QuickStats

    $procs = @(Get-KernelProcessList)
    $toKill = @()
    for ($i = 0; $i -lt $procs.Count; $i++) {
        if ($GameModeKeep -notcontains $procs[$i].Name) { $toKill += $i }
    }
    $killedNames = @($toKill | ForEach-Object { $procs[$_].Name })
    Kill-SelectedProcesses -Processes $procs -Indices $toKill
    Run-SystemOptimizations
    Set-GamePriority $game | Out-Null

    $after = Get-QuickStats
    $freedMB = [math]::Max(0, $after.FreeMB - $before.FreeMB)
    Write-Host ("  >> Freed {0} MB RAM. Keeping background apps closed while you play." -f $freedMB) -ForegroundColor Green
    Write-Host "  Press Q to stop guarding (settings restore automatically when the game closes)." -ForegroundColor DarkGray
    Write-Host ""

    # 0.5 ms timer resolution for smoother frame pacing (released when we stop)
    $timerSet = Set-TimerResolution -Enable
    if ($timerSet) { Write-Host "  >> Timer resolution: 0.5 ms (smoother frame pacing)" -ForegroundColor Green }

    $start = Get-Date
    $reClosed = 0
    $userOpened = @{}            # apps YOU opened mid-game - never re-closed
    $pings = New-Object System.Collections.ArrayList
    $minFree = [int]::MaxValue
    $nextSweep = (Get-Date).AddSeconds([int]$Config.WatcherIntervalSec)
    try {
        while (Get-Process -Id $game.Id -ErrorAction SilentlyContinue) {
            if (Test-QuitKey) { break }
            if ((Get-Date) -ge $nextSweep) {
                $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $MySessionId }
                # A visible window means you opened it on purpose (e.g. Discord, a guide in Chrome) - respect that
                foreach ($p in $running) {
                    if ($p.MainWindowHandle -ne [IntPtr]::Zero -and $killedNames -contains $p.ProcessName -and -not $userOpened[$p.ProcessName]) {
                        $userOpened[$p.ProcessName] = $true
                        Write-Log "User opened $($p.ProcessName) mid-game - leaving it alone"
                    }
                }
                # Never touch helpers of apps you opened (e.g. Discord's msedgewebview2 children)
                $parentOf = @{}
                Get-CimInstance Win32_Process -Filter "SessionId=$MySessionId" -ErrorAction SilentlyContinue |
                    ForEach-Object { $parentOf[[int]$_.ProcessId] = [int]$_.ParentProcessId }
                $userPids = @{}
                $running | Where-Object { $userOpened[$_.ProcessName] -or $GameModeKeep -contains $_.ProcessName } |
                    ForEach-Object { $userPids[$_.Id] = $true }
                $isUserChild = {
                    param($procId)
                    $cur = $procId
                    for ($d = 0; $d -lt 4; $d++) {
                        $par = $parentOf[$cur]
                        if (-not $par) { return $false }
                        if ($userPids[$par]) { return $true }
                        $cur = $par
                    }
                    return $false
                }
                # Background relaunchers (Slack tray, Edge WebView, updaters) get closed again
                $running | Where-Object { $killedNames -contains $_.ProcessName -and -not $userOpened[$_.ProcessName] -and -not (& $isUserChild $_.Id) } |
                    ForEach-Object {
                        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $reClosed++; Write-Log "Re-closed $($_.ProcessName)" } catch {}
                    }
                $nextSweep = (Get-Date).AddSeconds([int]$Config.WatcherIntervalSec)
            }
            $q = Get-QuickStats
            if ($q.FreeMB -lt $minFree) { $minFree = $q.FreeMB }
            $ping = Get-PingMs
            if ($ping -ge 0) { [void]$pings.Add($ping) }
            $pingStr = if ($ping -ge 0) { "$ping ms" } else { "--" }
            $played = (Get-Date) - $start
            Write-Host -NoNewline ("`r  [{0:hh\:mm\:ss}] {1} | RAM {2}% ({3} MB free) | CPU {4}% | ping {5} | re-closed {6}    " -f $played, $game.ProcessName, $q.UsedPct, $q.FreeMB, $q.CPU, $pingStr, $reClosed) -ForegroundColor Cyan
            Start-Sleep -Seconds 2
        }
    } finally {
        if ($timerSet) { Set-TimerResolution | Out-Null }
    }

    $mins = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
    $avgPing = if ($pings.Count) { [math]::Round(($pings | Measure-Object -Average).Average) } else { -1 }
    $maxPing = if ($pings.Count) { ($pings | Measure-Object -Maximum).Maximum } else { -1 }

    Write-Host ""
    Write-Host ""
    Write-Host "  SESSION SUMMARY" -ForegroundColor Yellow
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    Write-Host "    Game:            $($game.ProcessName)"
    Write-Host "    Played:          $mins min"
    Write-Host "    RAM freed:       $freedMB MB at start"
    Write-Host "    Lowest free RAM: $minFree MB"
    if ($avgPing -ge 0) { Write-Host "    Ping avg / max:  $avgPing / $maxPing ms" }
    Write-Host "    Apps re-closed:  $reClosed"
    if ($userOpened.Count) { Write-Host "    Left open (you): $($userOpened.Keys -join ', ')" }
    Write-Host ""

    Save-SessionHistory ([PSCustomObject]@{
        Date = (Get-Date -Format "yyyy-MM-dd HH:mm"); Game = $game.ProcessName; Minutes = $mins
        FreedMB = $freedMB; MinFreeMB = $minFree; AvgPing = $avgPing; MaxPing = $maxPing; ReClosed = $reClosed
    })
    Write-Log "Watcher session ended after $mins min, re-closed $reClosed apps"

    Write-Host "  Restoring normal mode..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    Restore-Normal
}

function Show-SessionHistory {
    Show-Banner
    Write-Host "  GAME SESSION HISTORY" -ForegroundColor Cyan
    Write-Host "  $('-' * 78)" -ForegroundColor DarkGray
    if (-not (Test-Path $HistoryFile)) { Write-Host "  No sessions yet - use GAME WATCHER to record them." -ForegroundColor DarkGray; return }
    $rows = @(Import-Csv $HistoryFile | Select-Object -Last 15)
    Write-Host ("  {0,-17} {1,-24} {2,6} {3,8} {4,9} {5,8}" -f "DATE", "GAME", "MIN", "FREED", "MIN FREE", "PING") -ForegroundColor White
    foreach ($r in $rows) {
        $pingTxt = if ([int]$r.AvgPing -ge 0) { "$($r.AvgPing)ms" } else { "--" }
        $g = $r.Game.Substring(0, [math]::Min(24, $r.Game.Length))
        Write-Host ("  {0,-17} {1,-24} {2,6} {3,6}MB {4,7}MB {5,8}" -f $r.Date, $g, $r.Minutes, $r.FreedMB, $r.MinFreeMB, $pingTxt)
    }
    Write-Host ""
}

# ============================================================
#  LIVE MONITOR - real-time dashboard
# ============================================================
function Start-LiveMonitor {
    $cores = [Environment]::ProcessorCount
    Clear-Host
    try { [Console]::CursorVisible = $false } catch {}
    try {
        while ($true) {
            if (Test-QuitKey) { break }
            $q = Get-QuickStats
            $perf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @("_Total", "Idle") }
            $topCpu = $perf | Group-Object { $_.Name -replace '#\d+$', '' } | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.Name
                    CPU  = [math]::Round((($_.Group | Measure-Object PercentProcessorTime -Sum).Sum / $cores), 1)
                    MB   = [math]::Round((($_.Group | Measure-Object WorkingSetPrivate -Sum).Sum / 1MB))
                }
            }
            $byCpu = $topCpu | Sort-Object CPU -Descending | Select-Object -First 8
            $byRam = $topCpu | Sort-Object MB -Descending | Select-Object -First 8

            $w = 100
            try { $w = [math]::Max(70, [Console]::WindowWidth - 1) } catch {}
            $lines = @()
            $lines += "  TURBO MODE - LIVE MONITOR            $(Get-Date -Format 'HH:mm:ss')   (Q = back)"
            $lines += "  " + ('=' * 64)
            $lines += ("  CPU  [{0}] {1,5}%" -f (Get-Bar $q.CPU), $q.CPU)
            $lines += ("  RAM  [{0}] {1,5}%  {2} / {3} MB" -f (Get-Bar $q.UsedPct), $q.UsedPct, ($q.TotalMB - $q.FreeMB), $q.TotalMB)
            $ping = Get-PingMs
            $lines += ("  NET  ping {0} = {1}" -f $Config.PingHost, $(if ($ping -ge 0) { "$ping ms" } else { "timeout" }))
            $lines += ""
            $lines += ("  {0,-28} {1,7}      {2,-24} {3,8}" -f "TOP CPU", "%", "TOP RAM (private)", "MB")
            $lines += "  " + ('-' * 64)
            for ($i = 0; $i -lt 8; $i++) {
                $c = $byCpu[$i]; $r = $byRam[$i]
                $cn = if ($c) { $c.Name.Substring(0, [math]::Min(28, $c.Name.Length)) } else { "" }
                $rn = if ($r) { $r.Name.Substring(0, [math]::Min(24, $r.Name.Length)) } else { "" }
                $lines += ("  {0,-28} {1,7}      {2,-24} {3,8}" -f $cn, $(if ($c) { $c.CPU } else { "" }), $rn, $(if ($r) { $r.MB } else { "" }))
            }
            $game = Get-RunningGame
            $lines += ""
            if ($game) { $lines += "  GAME RUNNING: $($game.ProcessName)  (priority: $($game.PriorityClass))" }
            else { $lines += "  No game running" }

            # Redraw in place (no flicker); fall back to clearing if the host has no real console
            try { [Console]::SetCursorPosition(0, 0) } catch { Clear-Host }
            foreach ($l in $lines) { Write-Host ([string]$l).PadRight($w).Substring(0, $w) }
            Start-Sleep -Seconds 2
        }
    } finally {
        try { [Console]::CursorVisible = $true } catch {}
    }
}

# ============================================================
#  STARTUP APPS MANAGER - same on/off switch Task Manager uses (reversible)
# ============================================================
function Get-StartupEntries {
    $approvedBase = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
    $sources = @(
        @{ Hive = "HKCU"; Run = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";             Approved = "HKCU:\$approvedBase\Run" },
        @{ Hive = "HKLM"; Run = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";             Approved = "HKLM:\$approvedBase\Run" },
        @{ Hive = "HKLM"; Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Approved = "HKLM:\$approvedBase\Run32" }
    )
    $entries = @()
    foreach ($s in $sources) {
        $props = Get-ItemProperty -Path $s.Run -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like "PS*") { continue }
            $entries += [PSCustomObject]@{ Name = $p.Name; Command = [string]$p.Value; Approved = $s.Approved; Scope = $s.Hive }
        }
    }
    $folders = @(
        @{ Path = [Environment]::GetFolderPath("Startup");       Approved = "HKCU:\$approvedBase\StartupFolder"; Scope = "HKCU" },
        @{ Path = [Environment]::GetFolderPath("CommonStartup"); Approved = "HKLM:\$approvedBase\StartupFolder"; Scope = "HKLM" }
    )
    foreach ($f in $folders) {
        Get-ChildItem -Path $f.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "desktop.ini" } | ForEach-Object {
            $entries += [PSCustomObject]@{ Name = $_.Name; Command = $_.FullName; Approved = $f.Approved; Scope = $f.Scope }
        }
    }
    foreach ($e in $entries) {
        $val = (Get-ItemProperty -Path $e.Approved -Name $e.Name -ErrorAction SilentlyContinue).($e.Name)
        # First byte: 2/6 = enabled, 3/7 = disabled; missing = enabled
        $enabled = $true
        if ($val -and $val.Length -gt 0) { $enabled = ($val[0] % 2 -eq 0) }
        $e | Add-Member -NotePropertyName Enabled -NotePropertyValue $enabled
    }
    return $entries
}

function Start-StartupManager {
    while ($true) {
        Show-Banner
        Write-Host "  STARTUP APPS - fewer startup apps = faster boot" -ForegroundColor Cyan
        Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
        $entries = @(Get-StartupEntries)
        if ($entries.Count -eq 0) { Write-Host "  No startup apps found." -ForegroundColor DarkGray; Read-Host "  Enter to go back"; return }
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $e = $entries[$i]
            $state = if ($e.Enabled) { "[ON ]" } else { "[OFF]" }
            $color = if ($e.Enabled) { "Green" } else { "DarkGray" }
            $cmd = $e.Command
            if ($cmd.Length -gt 38) { $cmd = $cmd.Substring(0, 35) + "..." }
            Write-Host -NoNewline ("  {0,3} " -f ($i + 1))
            Write-Host -NoNewline $state -ForegroundColor $color
            Write-Host (" {0,-26} {1}" -f $e.Name.Substring(0, [math]::Min(26, $e.Name.Length)), $cmd) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  <number> toggle on/off    back  return to menu" -ForegroundColor DarkGray
        $in = Read-Host "  >"
        if ($in -match '^(back|b|q)$' -or [string]::IsNullOrWhiteSpace($in)) { return }
        if ($in -match '^\d+$') {
            $idx = [int]$in - 1
            if ($idx -ge 0 -and $idx -lt $entries.Count) {
                $e = $entries[$idx]
                $first = if ($e.Enabled) { [byte]3 } else { [byte]2 }
                $bytes = [byte[]]@($first, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                try {
                    if (-not (Test-Path $e.Approved)) { New-Item -Path $e.Approved -Force | Out-Null }
                    Set-ItemProperty -Path $e.Approved -Name $e.Name -Value $bytes -Type Binary -ErrorAction Stop
                    $newState = if ($e.Enabled) { "DISABLED" } else { "ENABLED" }
                    Write-Host "    >> $($e.Name) $newState at startup" -ForegroundColor Green
                    Write-Log "Startup $newState : $($e.Name)"
                } catch {
                    Write-Host "    >> Could not change $($e.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
                Start-Sleep -Milliseconds 900
            }
        }
    }
}

# ============================================================
#  SYSTEM VIEW
# ============================================================
function Show-SystemView {
    Show-Banner
    $snap = Get-SystemSnapshot
    Show-Snapshot -Snap $snap -Label "FULL SYSTEM REPORT"

    Write-Host "  RUNNING APPS (your session):" -ForegroundColor Cyan
    Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
    foreach ($p in Get-KernelProcessList) {
        $memColor = "Green"
        if ($p.MemoryMB -gt 100) { $memColor = "Yellow" }
        if ($p.MemoryMB -gt 300) { $memColor = "Red" }
        $nameStr = $p.Name
        if ($nameStr.Length -gt 28) { $nameStr = $nameStr.Substring(0, 25) + "..." }
        $countStr = if ($p.Count -gt 1) { "$($p.Count)x" } else { "1" }
        Write-Host -NoNewline ("    {0,-28} {1,4} " -f $nameStr, $countStr)
        Write-Host -NoNewline ("{0,6} MB" -f $p.MemoryMB) -ForegroundColor $memColor
        Write-Host "  $($p.Category)"
    }
    Write-Host ""
}

# ============================================================
#  RESTORE
# ============================================================
function Restore-Normal {
    Show-Banner
    Write-Host "  RESTORING NORMAL MODE..." -ForegroundColor Cyan
    Write-Host ""

    $savedServices = $StateServices
    if (Test-Path $savedServices) {
        $svcs = Get-Content $savedServices
        foreach ($svc in $svcs) {
            if ($svc.Trim()) {
                try {
                    Start-Service -Name $svc.Trim() -ErrorAction SilentlyContinue
                    Write-Host "    [START] $($svc.Trim())" -ForegroundColor Green
                } catch {}
            }
        }
        Remove-Item $savedServices -Force
    }

    $savedPlan = $StatePowerPlan
    if (Test-Path $savedPlan) {
        $planLine = Get-Content $savedPlan | Select-String "GUID"
        if ($planLine -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            powercfg /setactive $Matches[1]
            Write-Host "    >> Power plan restored" -ForegroundColor Green
        }
        Remove-Item $savedPlan -Force
    }

    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -Value 20 -Type DWord -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" -Name "NonBestEffortLimit" -ErrorAction SilentlyContinue
    } catch {}
    Write-Log "Restored normal mode"

    Write-Host ""
    Write-Host "  RESTORED! Everything back to normal." -ForegroundColor Green
    Write-Host ""
}

# ============================================================
#  MAIN MENU
# ============================================================
function Show-Menu {
    while ($true) {
        Show-Banner

        $q = Get-QuickStats
        $ramColor = "Green"
        if ($q.UsedPct -gt 60) { $ramColor = "Yellow" }
        if ($q.UsedPct -gt 80) { $ramColor = "Red" }

        Write-Host -NoNewline "  RAM "
        Write-Host -NoNewline ("[{0}] {1}% used, {2} MB free" -f (Get-Bar $q.UsedPct 20), $q.UsedPct, $q.FreeMB) -ForegroundColor $ramColor
        Write-Host (" | CPU {0}% | Processes: {1}" -f $q.CPU, (Get-Process).Count)
        $game = Get-RunningGame
        if ($game) { Write-Host "  GAME RUNNING: $($game.ProcessName)" -ForegroundColor Green }
        Write-Host ""

        Write-Host "  SELECT MODE:" -ForegroundColor White
        Write-Host ""
        Write-Host "    [1] GAME MODE      Close EVERYTHING now for max FPS" -ForegroundColor Red
        Write-Host "    [2] GAME WATCHER   Auto-boost when a game starts, auto-restore when it ends" -ForegroundColor Red
        Write-Host "    [3] WORK MODE      Kill bloat, keep productivity apps" -ForegroundColor Green
        Write-Host "    [4] CUSTOM MODE    YOU pick what lives and what dies" -ForegroundColor Magenta
        Write-Host "    [5] DEEP CLEAN     Junk + dev caches + optimize (no kills)" -ForegroundColor Yellow
        Write-Host "    [6] LIVE MONITOR   Real-time CPU/RAM dashboard" -ForegroundColor Cyan
        Write-Host "    [7] SYSTEM VIEW    Full system stats + app list" -ForegroundColor Cyan
        Write-Host "    [8] STARTUP APPS   Turn startup apps on/off (faster boot)" -ForegroundColor Cyan
        Write-Host "    [9] RESTORE        Undo all optimizations" -ForegroundColor DarkYellow
        Write-Host "    [H] HISTORY        Past game sessions (RAM, ping, time)" -ForegroundColor DarkGray
        Write-Host "    [C] CONFIG         Edit games / keep lists" -ForegroundColor DarkGray
        Write-Host "    [0] EXIT" -ForegroundColor DarkGray
        Write-Host ""
        $choice = (Read-Host "  Enter choice").Trim().ToUpper()

        $pause = $true
        switch ($choice) {
            "1" { Start-GameMode }
            "2" { Start-GameWatcher }
            "3" { Start-WorkMode }
            "4" { Start-CustomMode }
            "5" { Start-DeepClean }
            "6" { Start-LiveMonitor; $pause = $false }
            "7" { Show-SystemView }
            "8" { Start-StartupManager; $pause = $false }
            "9" { Restore-Normal }
            "H" { Show-SessionHistory }
            "C" {
                Start-Process notepad.exe -ArgumentList "`"$ConfigFile`""
                Write-Host "  Opened config in Notepad - restart Turbo Mode after saving." -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
                $pause = $false
            }
            "0" { Write-Host "  Bye!" -ForegroundColor DarkGray; return }
            default { Write-Host "  Invalid!" -ForegroundColor Red; Start-Sleep -Seconds 1; $pause = $false }
        }

        if ($pause) {
            Write-Host ""
            Read-Host "  Press Enter to return to menu"
        }
    }
}

# --- RUN ---
switch ($Mode) {
    "Game"    { Start-GameMode }
    "Work"    { Start-WorkMode }
    "Clean"   { Start-DeepClean }
    "Watch"   { Start-GameWatcher }
    "Monitor" { Start-LiveMonitor }
    "Restore" { Restore-Normal }
    default   { Show-Menu }
}
if ($Mode -ne "Menu" -and -not $Yes) { Read-Host "  Press Enter to exit" }
