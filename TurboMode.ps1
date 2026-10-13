# ============================================================
#  TURBO MODE v4.0 - Ultimate System Optimizer
#  Real stats | Temp cleanup | Kernel-level | Before/After
# ============================================================

# Self-elevate to admin if not already
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $exe = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ($exe) {
        Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$exe`""
    } else {
        Write-Host "  ERROR: Please run as Administrator!" -ForegroundColor Red
        Read-Host "  Press Enter to exit"
    }
    exit
}

$Host.UI.RawUI.WindowTitle = "TURBO MODE v4.0"

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
    Write-Host "  |        >>> T U R B O   M O D E   v 4 . 0 <<<            |" -ForegroundColor Red
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
    $rb = Read-Host "    Also empty the Recycle Bin? (y/N)"
    if ($rb -match '^(y|yes)$') {
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
    $confirm = Read-Host "    Save your work! Continue? (Y/n)"
    if ($confirm -match '^(n|no)$') { Write-Host "  Cancelled." -ForegroundColor DarkGray; return }
    Kill-SelectedProcesses -Processes $procs -Indices $toKill

    Write-Host "  [2/4] CLEANING TEMP/JUNK..." -ForegroundColor Yellow
    Clean-TempFiles

    Write-Host "  [3/4] SYSTEM OPTIMIZATIONS..." -ForegroundColor Yellow
    Run-SystemOptimizations

    Write-Host "  [4/4] VALORANT PRIORITY..." -ForegroundColor Yellow
    $val = Get-Process -Name "VALORANT-Win64-Shipping" -ErrorAction SilentlyContinue
    if ($val) {
        try {
            $val.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
            Write-Host "    >> Valorant = HIGH priority!" -ForegroundColor Green
        } catch { Write-Host "    ~ Anti-cheat blocked" -ForegroundColor DarkGray }
    } else {
        Write-Host "    >> Launch Valorant now!" -ForegroundColor Cyan
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
    Run-SystemOptimizations

    Write-Host "  Taking AFTER snapshot..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
    $after = Get-SystemSnapshot

    Show-Comparison -Before $before -After $after
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
    Show-Banner

    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedPct = [math]::Round((($totalGB - $freeGB) / $totalGB) * 100)
    $procCount = (Get-Process).Count

    $ramColor = "Green"
    if ($usedPct -gt 60) { $ramColor = "Yellow" }
    if ($usedPct -gt 80) { $ramColor = "Red" }

    Write-Host -NoNewline "  RAM: "
    Write-Host -NoNewline "${freeGB}GB free / ${totalGB}GB (${usedPct}% used)" -ForegroundColor $ramColor
    Write-Host " | Processes: $procCount"
    Write-Host ""

    Write-Host "  SELECT MODE:" -ForegroundColor White
    Write-Host ""
    Write-Host "    [1] GAME MODE      Kill EVERYTHING for Valorant (max FPS)" -ForegroundColor Red
    Write-Host "    [2] WORK MODE      Kill bloat, keep productivity apps" -ForegroundColor Green
    Write-Host "    [3] CUSTOM MODE    YOU pick what lives and what dies" -ForegroundColor Magenta
    Write-Host "    [4] DEEP CLEAN     Clean temp/junk files + optimize (no kills)" -ForegroundColor Yellow
    Write-Host "    [5] SYSTEM VIEW    Full system stats + process list" -ForegroundColor Cyan
    Write-Host "    [6] RESTORE        Undo all optimizations" -ForegroundColor DarkYellow
    Write-Host "    [7] EXIT" -ForegroundColor DarkGray
    Write-Host ""
    $choice = Read-Host "  Enter (1-7)"

    switch ($choice) {
        "1" { Start-GameMode }
        "2" { Start-WorkMode }
        "3" { Start-CustomMode }
        "4" { Start-DeepClean }
        "5" {
            Show-Banner
            $snap = Get-SystemSnapshot
            Show-Snapshot -Snap $snap -Label "FULL SYSTEM REPORT"

            Write-Host "  RUNNING PROCESSES (Kernel Level):" -ForegroundColor Cyan
            Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
            $procs = Get-KernelProcessList
            foreach ($p in $procs) {
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
            Read-Host "  Press Enter to go back"
            Show-Menu
            return
        }
        "6" { Restore-Normal }
        "7" {
            Write-Host "  Bye!" -ForegroundColor DarkGray
            return
        }
        default {
            Write-Host "  Invalid!" -ForegroundColor Red
            Start-Sleep -Seconds 1
            Show-Menu
            return
        }
    }

    Write-Host ""
    Read-Host "  Press Enter to return to menu"
    Show-Menu
}

# --- RUN ---
Show-Menu
