<div align="center">

# ⚡ TURBO MODE v4.0

**One-click Windows performance booster: kill background apps, wipe junk, and unlock max-performance settings, with a full before/after report.**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![C#](https://img.shields.io/badge/C%23-.NET%204-512BD4?style=for-the-badge&logo=csharp&logoColor=white)

</div>

---

## ✨ Features

| Mode | What it does |
|---|---|
| 🎮 **Game Mode** | Closes every app in your session except the game (Valorant + Vanguard kept alive), cleans junk, sets max performance, raises game priority |
| 💼 **Work Mode** | Kills only gaming / media / bloat apps, and keeps your IDE, browser, Slack, Teams and Docker running |
| 🎯 **Custom Mode** | Interactive picker: toggle by number, ranges (`3-7`), `big` (>100 MB), `cat Browser`, and save/load **profiles** |
| 🧹 **Deep Clean** | Junk cleanup + optimizations, with no process killing |
| 📊 **System View** | Live RAM / commit / cache / CPU / threads / handles / disk, plus every process grouped and categorized |
| ↩️ **Restore** | Restarts stopped services, restores your original power plan and network settings |

Every mode prints a **BEFORE vs AFTER** table and an optimization score out of 100.

### Under the hood
- **Standby-list purge** via `NtSetSystemInformation` (same technique as RAMMap / ISLC)
- **Working-set trimming** with `EmptyWorkingSet` on every process
- **Service stop**: Windows Search, SysMain, telemetry, Xbox, Fax, Maps…
- **Ultimate / High Performance** power plan
- **Network**: DNS flush, multimedia network throttling disabled
- **Junk cleanup**: temp folders, Windows Update cache, browser caches (Chrome/Edge/Brave), crash dumps, WER reports, D3D shader cache, Delivery Optimization

## 🛡️ Safety design

- **Never touches Session 0.** Windows services, drivers, antivirus and anti-cheat run there; only apps in *your* desktop session can be killed.
- **Hard protect list** for shell/UI processes (`explorer`, `dwm`, `csrss`, `lsass`, Defender, audio, GPU drivers…).
- **Protects itself and its parent chain**, so it can't kill its own console window.
- **Game Mode asks for confirmation** and lists every app it will close first.
- **Recycle Bin is opt-in.** It is never emptied silently.
- Doesn't delete Prefetch / icon / font caches (removing those makes Windows *slower*).
- All state is saved in `%USERPROFILE%\.turbomode\` so **Restore** always works, and every kill is logged to `turbomode.log`.

## 🚀 Usage

Double-click **`TURBO MODE.bat`** (or `TurboMode.exe`) and accept the admin prompt.

Or run the script directly:
```powershell
powershell -ExecutionPolicy Bypass -File .\TurboMode.ps1
```

## 🔨 Build from source

The `.exe` is a small C# launcher that elevates, purges standby memory, and runs the embedded `TurboMode.ps1`.

```powershell
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /target:exe /out:TurboMode.exe /win32manifest:app.manifest /resource:TurboMode.ps1,TurboMode.ps1 TurboMode.cs
& $csc /nologo /target:library /out:KernelMemOptimizer.dll KernelMemOptimizer.cs
```

## 📁 Project structure

```
TurboMode.ps1            Main optimizer (menu, modes, cleanup, stats)
TurboMode.cs             Native launcher: UAC elevation + standby purge + embedded script
KernelMemOptimizer.cs    Standby-list purge helper DLL used by the script
app.manifest             requireAdministrator manifest
TURBO MODE.bat           Double-click launcher
```

## 📝 Changelog

**v4.0**
- 🐛 Fixed crash when killing processes (`$pid` is a read-only PowerShell variable)
- 🐛 Fixed error flood on every snapshot (`Measure-Object` on thread collections)
- 🐛 Restore now works after cleanup (state moved out of `%TEMP%`)
- 🐛 Kill count is now accurate (failed kills are no longer counted)
- ✨ Session-based targeting: kills more user apps, never system services
- ✨ Kill preview + confirmation, opt-in Recycle Bin, activity log, menu loops after each action
- 🧹 Removed slowdown-causing cleanups (Prefetch, icon/font cache)

## ⚠️ Disclaimer

Closing apps discards unsaved work, so save before running Game Mode. Use at your own risk.
