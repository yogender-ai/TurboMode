using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Security.Principal;
using System.Runtime.InteropServices;

namespace TurboModeApp
{
    public class Program
    {
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

        [DllImport("ntdll.dll")]
        private static extern uint NtSetSystemInformation(int SystemInformationClass, ref int SystemInformation, int SystemInformationLength);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll")]
        private static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

        [DllImport("kernel32.dll")]
        private static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID
        {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_PRIVILEGES
        {
            public uint PrivilegeCount;
            public LUID Luid;
            public uint Attributes;
        }

        private const int STD_OUTPUT_HANDLE = -11;
        private const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

        private static bool IsAdministrator()
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }

        public static void PurgeStandbyMemory()
        {
            try
            {
                IntPtr token;
                if (OpenProcessToken(GetCurrentProcess(), 0x0028, out token))
                {
                    try
                    {
                        LUID luid;
                        if (LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid))
                        {
                            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES
                            {
                                PrivilegeCount = 1,
                                Luid = luid,
                                Attributes = 2
                            };
                            AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
                        }
                    }
                    finally
                    {
                        CloseHandle(token);
                    }
                }
                int cmd = 4; // PurgeStandbyList
                NtSetSystemInformation(80, ref cmd, sizeof(int));
                int cmd2 = 2; // EmptyWorkingSets
                NtSetSystemInformation(80, ref cmd2, sizeof(int));
            }
            catch { }
        }

        public static int Main(string[] args)
        {
            try
            {
                Console.Title = "TURBO MODE v4.0 - Ultimate System Optimizer";

                // Enable VT100 colors if available
                try
                {
                    IntPtr handle = GetStdHandle(STD_OUTPUT_HANDLE);
                    uint mode;
                    if (GetConsoleMode(handle, out mode))
                    {
                        SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
                    }
                }
                catch { }

                // Check Administrator privileges
                if (!IsAdministrator())
                {
                    ProcessStartInfo elevateInfo = new ProcessStartInfo
                    {
                        FileName = Assembly.GetExecutingAssembly().Location,
                        UseShellExecute = true,
                        Verb = "runas"
                    };

                    try
                    {
                        Process proc = Process.Start(elevateInfo);
                        return 0;
                    }
                    catch
                    {
                        Console.ForegroundColor = ConsoleColor.Red;
                        Console.WriteLine("\n  [ERROR] Administrator privileges are required for Turbo Mode to operate at kernel level.");
                        Console.ResetColor();
                        Console.WriteLine("  Press any key to exit...");
                        Console.ReadKey(true);
                        return 1;
                    }
                }

                // Purge Standby memory right at launch
                PurgeStandbyMemory();

                // Determine path to TurboMode.ps1
                string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
                string scriptPath = Path.Combine(exeDir, "TurboMode.ps1");

                if (!File.Exists(scriptPath))
                {
                    // Fallback to user home directory cache
                    string userDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".turbomode");
                    if (!Directory.Exists(userDir))
                    {
                        Directory.CreateDirectory(userDir);
                    }
                    scriptPath = Path.Combine(userDir, "TurboMode.ps1");

                    // Extract embedded script
                    using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("TurboMode.ps1"))
                    {
                        if (stream != null)
                        {
                            using (FileStream fs = new FileStream(scriptPath, FileMode.Create, FileAccess.Write))
                            {
                                stream.CopyTo(fs);
                            }
                        }
                    }
                }

                if (!File.Exists(scriptPath))
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine("\n  [ERROR] Could not locate TurboMode.ps1 script!");
                    Console.ResetColor();
                    Console.WriteLine("  Press any key to exit...");
                    Console.ReadKey(true);
                    return 1;
                }

                // Execute PowerShell with bypass
                string psExe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
                if (!File.Exists(psExe))
                {
                    psExe = "powershell.exe";
                }

                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = psExe,
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\"",
                    UseShellExecute = false
                };

                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    return p.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("\n  [UNHANDLED ERROR] " + ex.Message);
                Console.ResetColor();
                Console.WriteLine("  Press any key to exit...");
                Console.ReadKey(true);
                return 1;
            }
        }
    }
}
