<div align="center">

<img src="https://raw.githubusercontent.com/yogender-ai/TurboMode/main/turbo.ico" width="96" alt="Turbo Mode">

# ⚡ TURBO MODE v5.0

**A Windows performance booster for gamers and developers. It auto-boosts when your game launches, guards your FPS while you play, and restores everything when you quit.**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![C#](https://img.shields.io/badge/C%23-.NET%204-512BD4?style=for-the-badge&logo=csharp&logoColor=white)

</div>

---

## ✨ Features

| # | Mode | What it does |
|---|---|---|
| 1 | 🎮 **Game Mode** | Closes every app in your session except your game + anti-cheat, cleans junk, sets max performance, raises game priority |
| 2 | 🎯 **Game Watcher** | **Set and forget.** Waits for any game in your list, boosts automatically, keeps relaunching background apps closed while you play, then **auto-restores** when the game exits |
| 3 | 💼 **Work Mode** | Kills gaming / media / bloat apps only, and keeps your IDE, browser, Slack, Teams and Docker |
| 4 | 🧩 **Custom Mode** | Interactive picker: numbers, ranges (`3-7`), `big` (>100 MB), `cat Browser`, and save/load **profiles** |
| 5 | 🧹 **Deep Clean** | Junk files + **developer caches** (npm, pip, yarn, pnpm, NuGet, Go) + optimizations, with no kills |
| 6 | 📈 **Live Monitor** | Real-time CPU / RAM bars, ping, and the top 8 apps by CPU and RAM. Flicker-free redraw. |
| 7 | 📊 **System View** | Full stats: RAM / commit / cache / threads / handles / disk + every app categorized |
| 8 | 🚀 **Startup Apps** | Turn startup apps on/off using the same switch Task Manager uses (fully reversible) |
| 9 | ↩️ **Restore** | Restarts stopped services, restores your power plan and network settings |
| H | 📜 **History** | Every Game Watcher session: game, minutes, RAM freed, lowest free RAM, avg/max ping |

Every boost prints a **BEFORE vs AFTER** table and an optimization score out of 100.

### 🎯 Game Watcher in detail
```
Waiting for a game to launch...  21:04:11
>> DETECTED: VALORANT-Win64-Shipping - BOOSTING!
>> Timer resolution: 0.5 ms (smoother frame pacing)
[00:42:17] VALORANT-Win64-Shipping | RAM 51% (7840 MB free) | CPU 38% | ping 24 ms | re-closed 6

SESSION SUMMARY
  Played: 42.3 min | RAM freed: 2310 MB | Ping avg/max: 26 / 61 ms | Apps re-closed: 6
```
- **0.5 ms timer resolution** while you play (the same technique as ISLC). Windows releases it automatically when Turbo Mode exits.
- **Respects you.** If you open Discord or a browser mid-game (any app with a visible window), it and its helper processes are never closed again.
- **Re-closes background relaunchers** (Slack tray, Edge WebView, updaters) every 15 s.

### ⚙️ Under the hood
- **Standby-list purge** via `NtSetSystemInformation` (same as RAMMap)
- **Working-set trimming** with `EmptyWorkingSet`
- **Service stop**: Windows Search, SysMain, telemetry, Xbox, Fax, Maps…
- **Ultimate / High Performance** power plan
- **Network**: DNS flush, multimedia network throttling disabled

## 🛡️ Safety design
- **Never touches Session 0.** Windows services, drivers, antivirus and anti-cheat (Vanguard) run there.
- Hard protect-list for shell/UI processes, and it **protects its own process chain**.
- Game Mode **lists what it will close and asks first**. The Recycle Bin is never emptied without an explicit "yes".
- Doesn't delete Prefetch / icon / font caches (removing those makes Windows *slower*).
- All state is saved in `%USERPROFILE%\.turbomode\`, so Restore always works. Every action is logged to `turbomode.log`.

## 🚀 Usage

Double-click **`TurboMode.exe`** (or `TURBO MODE.bat`) and accept the admin prompt.

**One-click shortcuts / command line:**
```powershell
TurboMode.exe                    # menu
TurboMode.exe -Mode Watch        # Game Watcher
TurboMode.exe -Mode Monitor      # Live Monitor
TurboMode.exe -Mode Game -Yes    # instant Game Mode, no prompts
TurboMode.exe -Mode Clean        # Deep Clean
TurboMode.exe -Mode Restore      # undo everything
```
Modes: `Menu | Game | Work | Clean | Watch | Monitor | Restore`. `-Yes` skips confirmations but never empties the Recycle Bin.

## 🔧 Configuration

`%USERPROFILE%\.turbomode\config.json` is created on first run (or press **C** in the menu):

```json
{
  "GameProcesses": ["VALORANT-Win64-Shipping", "cs2", "FortniteClient-Win64-Shipping", "r5apex", "GTA5"],
  "ExtraGameKeep": ["Discord"],
  "ExtraWorkKeep": [],
  "WatcherIntervalSec": 15,
  "PingHost": "1.1.1.1"
}
```
| Key | Meaning |
|---|---|
| `GameProcesses` | Process names (without `.exe`) treated as games |
| `ExtraGameKeep` | Apps Game Mode / Watcher must never close |
| `ExtraWorkKeep` | Extra apps Work Mode keeps |
| `WatcherIntervalSec` | How often the watcher re-closes relaunched apps |
| `PingHost` | Host used for the ping readout (e.g. your game server region) |

## 🔨 Build from source
```powershell
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:exe /out:TurboMode.exe /win32manifest:app.manifest /win32icon:turbo.ico /resource:TurboMode.ps1,TurboMode.ps1 TurboMode.cs
& $csc /nologo /target:library /out:KernelMemOptimizer.dll KernelMemOptimizer.cs
```
The `.exe` is a small C# launcher: it elevates, purges standby memory, forwards arguments, and runs the embedded `TurboMode.ps1`. It still works if you copy the exe alone.

## 📁 Files
```
TurboMode.ps1            The optimizer (menu, modes, watcher, monitor, startup manager)
TurboMode.cs             Native launcher (UAC + standby purge + embedded script + arg forwarding)
KernelMemOptimizer.cs    Standby-list purge helper DLL
turbo.ico                App icon (16-256 px)
app.manifest             requireAdministrator manifest
TURBO MODE.bat           Double-click launcher
```

## 📝 Changelog

**v5.0**
- ✨ **Game Watcher**: auto-boost on game launch, guard while playing, auto-restore on exit
- ✨ **0.5 ms timer resolution** during game sessions
- ✨ **Live Monitor**: real-time CPU/RAM/ping dashboard
- ✨ **Startup Apps manager** (Task-Manager-compatible on/off)
- ✨ **Dev cache cleanup**: npm / pip / yarn / pnpm / NuGet / Go
- ✨ **Session history** (`history.csv`) + **config.json** + **command-line modes**
- ✨ Works for any game, not just Valorant; new app icon

**v4.0**
- 🐛 Fixed crash when killing processes (`$pid` is read-only in PowerShell)
- 🐛 Fixed error flood on every snapshot (thread counting)
- 🐛 Restore works after cleanup; accurate kill count
- ✨ Session-based targeting, kill preview, opt-in Recycle Bin, activity log

## ⚠️ Disclaimer
Closing apps discards unsaved work, so save before Game Mode. Use at your own risk.
