// ============================================================
//  TURBO MODE v5.1 - Desktop app
//  A friendly window on top of the TurboMode.ps1 engine.
//  Build: see README (csc, .NET Framework 4.x - nothing to install)
// ============================================================
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace TurboModeApp
{
    static class Theme
    {
        public static readonly Color Bg      = Color.FromArgb(15, 17, 23);
        public static readonly Color Panel   = Color.FromArgb(24, 27, 36);
        public static readonly Color Card    = Color.FromArgb(32, 36, 48);
        public static readonly Color CardHi  = Color.FromArgb(44, 49, 66);
        public static readonly Color Border  = Color.FromArgb(52, 58, 78);
        public static readonly Color Text    = Color.FromArgb(232, 235, 242);
        public static readonly Color Muted   = Color.FromArgb(140, 148, 168);
        public static readonly Color Red     = Color.FromArgb(255, 61, 96);
        public static readonly Color Orange  = Color.FromArgb(255, 150, 50);
        public static readonly Color Green   = Color.FromArgb(46, 204, 113);
        public static readonly Color Blue    = Color.FromArgb(64, 156, 255);
        public static readonly Color Purple  = Color.FromArgb(168, 110, 255);
        public static readonly Color Yellow  = Color.FromArgb(255, 205, 40);

        // Windows display scaling (1.0 = 100%, 1.5 = 150%...). Fonts scale by themselves; pixel sizes use P().
        public static float Scale = 1f;
        public static int P(float v) { return (int)Math.Round(v * Scale); }

        public static Font F(float size, FontStyle style = FontStyle.Regular)
        {
            return new Font("Segoe UI", size, style);
        }
    }

    // ---------- Small custom controls ----------

    class Gauge : Panel
    {
        public string Title = "";
        public string Value = "--";
        public string Sub = "";
        public double Percent = 0;
        public Color Accent = Theme.Blue;

        public Gauge()
        {
            DoubleBuffered = true;
            BackColor = Theme.Card;
            Height = Theme.P(100);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            using (var b = new SolidBrush(Theme.Muted)) g.DrawString(Title.ToUpper(), Theme.F(8.5f, FontStyle.Bold), b, Theme.P(14), Theme.P(10));
            using (var b = new SolidBrush(Theme.Text)) g.DrawString(Value, Theme.F(17f, FontStyle.Bold), b, Theme.P(12), Theme.P(26));
            using (var b = new SolidBrush(Theme.Muted)) g.DrawString(Sub, Theme.F(8.5f), b, Theme.P(14), Theme.P(62));

            var track = new Rectangle(Theme.P(14), Height - Theme.P(14), Width - Theme.P(28), Theme.P(6));
            using (var b = new SolidBrush(Theme.Border)) g.FillRectangle(b, track);
            int w = (int)(track.Width * Math.Max(0, Math.Min(100, Percent)) / 100.0);
            Color c = Accent;
            if (Percent > 85) c = Theme.Red; else if (Percent > 65) c = Theme.Orange;
            if (w > 0) using (var b = new SolidBrush(c)) g.FillRectangle(b, new Rectangle(track.X, track.Y, w, track.Height));
        }
    }

    class ActionCard : Button
    {
        public string Heading = "";
        public string Detail = "";
        public string Glyph = "";
        public Color Accent = Theme.Blue;
        bool hover;

        public ActionCard()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            BackColor = Theme.Card;
            ForeColor = Theme.Text;
            Cursor = Cursors.Hand;
            Height = Theme.P(92);
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            Color bg = !Enabled ? Theme.Panel : (hover ? Theme.CardHi : Theme.Card);
            g.Clear(bg);
            using (var b = new SolidBrush(Enabled ? Accent : Theme.Border)) g.FillRectangle(b, 0, 0, Theme.P(5), Height);

            int cs = Theme.P(44);
            var circle = new Rectangle(Theme.P(16), (Height - cs) / 2, cs, cs);
            using (var b = new SolidBrush(Color.FromArgb(Enabled ? 45 : 20, Accent))) g.FillEllipse(b, circle);
            using (var b = new SolidBrush(Enabled ? Accent : Theme.Muted))
            using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                g.DrawString(Glyph, new Font("Segoe UI Symbol", 16f, FontStyle.Bold), b, circle, sf);

            using (var b = new SolidBrush(Enabled ? Theme.Text : Theme.Muted)) g.DrawString(Heading, Theme.F(12f, FontStyle.Bold), b, Theme.P(72), Theme.P(12));
            using (var b = new SolidBrush(Theme.Muted))
                g.DrawString(Detail, Theme.F(8.75f), b, new RectangleF(Theme.P(73), Theme.P(38), Width - Theme.P(82), Height - Theme.P(40)));
        }
    }

    class NavButton : Button
    {
        public bool Active;
        public NavButton(string text)
        {
            Text = "   " + text;
            TextAlign = ContentAlignment.MiddleLeft;
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            FlatAppearance.MouseOverBackColor = Theme.Card;
            Font = Theme.F(10.5f, FontStyle.Bold);
            ForeColor = Theme.Muted;
            BackColor = Theme.Panel;
            Height = Theme.P(46);
            Dock = DockStyle.Top;
            Cursor = Cursors.Hand;
        }
        public void SetActive(bool a)
        {
            Active = a;
            BackColor = a ? Theme.Card : Theme.Panel;
            ForeColor = a ? Theme.Text : Theme.Muted;
            Invalidate();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Active) using (var b = new SolidBrush(Theme.Red)) e.Graphics.FillRectangle(b, 0, Theme.P(8), Theme.P(4), Height - Theme.P(16));
        }
    }

    class StartupEntry
    {
        public string Name, Command, Location;
        public RegistryKey Root;
        public string ApprovedPath;
        public bool Enabled;
    }

    // ---------- Main window ----------

    public class MainForm : Form
    {
        readonly string turboDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".turbomode");
        string scriptPath;

        Panel content, header;
        NavButton navDash, navStartup, navHistory, navSettings, navHelp;
        Panel pageDash, pageStartup, pageHistory, pageSettings, pageHelp;

        Gauge gCpu, gRam, gPing, gDisk;
        ActionCard cGame, cWatch, cWork, cClean, cRestore, cConsole;
        CheckBox chkDevCaches, chkRecycle;
        RichTextBox log;
        Label lblStatus, lblGame;
        ProgressBar busy;
        ListView lvTop, lvStartup, lvHistory;
        TextBox txtGames, txtGameKeep, txtWorkKeep, txtPingHost;
        NumericUpDown numInterval;

        Process running;
        string runningMode;
        bool loadingStartup;
        PerformanceCounter cpuCounter;
        Timer statsTimer;
        int tick;
        string[] gameNames = new string[0];
        string pingHost = "1.1.1.1";
        Microsoft.VisualBasic.Devices.ComputerInfo ci = new Microsoft.VisualBasic.Devices.ComputerInfo();

        public MainForm(string[] args)
        {
            Text = "TURBO MODE v5.1";
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            BackColor = Theme.Bg;
            ForeColor = Theme.Text;
            Font = Theme.F(9.5f);
            MinimumSize = new Size(Theme.P(1080), Theme.P(720));
            Size = new Size(Theme.P(1180), Theme.P(800));
            var wa = Screen.PrimaryScreen.WorkingArea;
            if (Width > wa.Width || Height > wa.Height) { MinimumSize = new Size(Math.Min(MinimumSize.Width, wa.Width), Math.Min(MinimumSize.Height, wa.Height)); WindowState = FormWindowState.Maximized; }
            StartPosition = FormStartPosition.CenterScreen;

            Directory.CreateDirectory(turboDir);
            scriptPath = LocateEngine();
            LoadConfig();

            BuildHeader();
            BuildNav();
            content = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg, Padding = new Padding(Theme.P(22), Theme.P(16), Theme.P(22), Theme.P(16)) };
            Controls.Add(content);
            content.BringToFront();

            pageDash = BuildDashboard();
            pageStartup = BuildStartupPage();
            pageHistory = BuildHistoryPage();
            pageSettings = BuildSettingsPage();
            pageHelp = BuildHelpPage();
            foreach (var p in new[] { pageDash, pageStartup, pageHistory, pageSettings, pageHelp }) { p.Dock = DockStyle.Fill; p.Visible = false; content.Controls.Add(p); }
            ShowPage(pageDash, navDash);

            try { cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total"); cpuCounter.NextValue(); } catch { cpuCounter = null; }
            statsTimer = new Timer { Interval = 1500 };
            statsTimer.Tick += delegate { RefreshStats(); };
            statsTimer.Start();
            RefreshStats();

            Log("Welcome to TURBO MODE. Pick an action above - every action is explained in the Help tab.", Theme.Muted);
            if (scriptPath == null) Log("ERROR: engine script TurboMode.ps1 not found.", Theme.Red);

            FormClosing += OnClosingForm;
            if (args.Any(a => a.Equals("--watch", StringComparison.OrdinalIgnoreCase)))
                Shown += delegate { StartWatcher(); };
            // --page=startup|history|settings|help opens directly on that tab
            string page = args.Where(a => a.StartsWith("--page=", StringComparison.OrdinalIgnoreCase)).Select(a => a.Substring(7).ToLower()).FirstOrDefault();
            if (page == "startup") { LoadStartup(); ShowPage(pageStartup, navStartup); }
            else if (page == "history") { LoadHistory(); ShowPage(pageHistory, navHistory); }
            else if (page == "settings") ShowPage(pageSettings, navSettings);
            else if (page == "help") ShowPage(pageHelp, navHelp);
        }

        // ---------- Engine ----------

        string LocateEngine()
        {
            string exeDir = Path.GetDirectoryName(Application.ExecutablePath);
            string local = Path.Combine(exeDir, "TurboMode.ps1");
            if (File.Exists(local)) return local;
            try
            {
                string dir = Path.Combine(turboDir, "engine");
                Directory.CreateDirectory(dir);
                string target = Path.Combine(dir, "TurboMode.ps1");
                using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("TurboMode.ps1"))
                {
                    if (s == null) return null;
                    using (var fs = new FileStream(target, FileMode.Create, FileAccess.Write)) s.CopyTo(fs);
                }
                return target;
            }
            catch { return null; }
        }

        const string WatchIdleText = "Auto-boost when your game starts, auto-restore after.";

        bool IsBusy { get { return running != null && !running.HasExited; } }

        void RunEngine(string mode, string extra, string friendly)
        {
            if (scriptPath == null) { MessageBox.Show(this, "TurboMode.ps1 engine is missing.", "TURBO MODE", MessageBoxButtons.OK, MessageBoxIcon.Error); return; }
            if (IsBusy) { MessageBox.Show(this, "Please wait - \"" + runningMode + "\" is still running.", "TURBO MODE", MessageBoxButtons.OK, MessageBoxIcon.Information); return; }
            try { File.Delete(Path.Combine(turboDir, "stop.flag")); } catch { }

            var psi = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -Mode " + mode + " -Yes " + extra,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            running = new Process { StartInfo = psi, EnableRaisingEvents = true };
            running.OutputDataReceived += (s, e) => { if (e.Data != null) BeginInvoke(new Action<string>(OnEngineLine), e.Data); };
            running.ErrorDataReceived += (s, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) BeginInvoke(new Action<string>(OnEngineError), e.Data); };
            running.Exited += (s, e) => { try { BeginInvoke(new Action(OnEngineDone)); } catch { } };

            runningMode = friendly;
            Log("", Theme.Muted);
            Log("==== " + friendly.ToUpper() + "  (" + DateTime.Now.ToString("HH:mm:ss") + ") ====", Theme.Yellow);
            running.Start();
            running.BeginOutputReadLine();
            running.BeginErrorReadLine();
            SetBusy(true, friendly + " running...");
        }

        void OnEngineLine(string line)
        {
            string t = line.TrimEnd();
            if (t.Length == 0) return;
            // Live watcher status lines update the status bar instead of flooding the log
            if (System.Text.RegularExpressions.Regex.IsMatch(t, @"^\s*\[\d\d:\d\d:\d\d\]") || t.Contains("Waiting for a game"))
            {
                lblStatus.Text = t.Trim();
                return;
            }
            if (t.Trim().StartsWith("+===") || t.Trim().StartsWith("|")) return; // console banner
            Color c = Theme.Text;
            string u = t.ToUpper();
            if (u.Contains("ERROR") || u.Contains(" X ")) c = Theme.Red;
            else if (u.Contains(">>") || u.Contains("OK") || u.Contains("RESTORED")) c = Theme.Green;
            else if (u.Contains("[DEL]") || u.Contains("[STOP]") || u.Contains("[OPT]") || u.Contains("[DEV]")) c = Theme.Orange;
            else if (u.Contains("BEFORE") || u.Contains("AFTER") || u.Contains("SUMMARY") || u.Contains("SCORE")) c = Theme.Yellow;
            else if (t.StartsWith("    ~") || u.Contains("PROTECTED")) c = Theme.Muted;
            Log(t, c);
        }

        void OnEngineError(string line)
        {
            if (line.Contains("handle is invalid")) return; // harmless console-only call
            Log("  ! " + line, Theme.Red);
        }

        void OnEngineDone()
        {
            Log("==== " + (runningMode ?? "Task").ToUpper() + " FINISHED ====", Theme.Green);
            SetBusy(false, "Ready");
            cWatch.Heading = "GAME WATCHER";
            cWatch.Detail = WatchIdleText;
            cWatch.Invalidate();
            LoadHistory();
        }

        void SetBusy(bool on, string status)
        {
            busy.Visible = on;
            lblStatus.Text = status;
            foreach (var c in new[] { cGame, cWork, cClean, cRestore }) c.Enabled = !on;
            cWatch.Enabled = !on || runningMode == "Game Watcher";
        }

        // ---------- Actions ----------

        void StartGameMode()
        {
            var r = MessageBox.Show(this,
                "GAME MODE closes every open app except your game and its anti-cheat:\n\n" +
                "  - browsers, chat apps, launchers and background helpers\n" +
                "  - then frees RAM and switches to max performance (no slow disk cleanup)\n\n" +
                "SAVE YOUR WORK FIRST. Unsaved changes in closed apps are lost.\n\nContinue?",
                "Start Game Mode", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
            if (r == DialogResult.Yes) RunEngine("Game", CleanupArgs(), "Game Mode");
        }

        void StartWatcher()
        {
            if (IsBusy && runningMode == "Game Watcher")
            {
                File.WriteAllText(Path.Combine(turboDir, "stop.flag"), "stop");
                lblStatus.Text = "Stopping watcher and restoring...";
                return;
            }
            var r = MessageBox.Show(this,
                "GAME WATCHER waits in the background for any game in your list:\n\n  " +
                string.Join(", ", gameNames) +
                "\n\nWhen one starts it closes background apps, boosts performance, and keeps\n" +
                "relaunching helpers closed. Apps YOU open while playing are left alone.\n" +
                "When the game closes, everything is restored automatically.\n\n" +
                "Save your work in other apps before launching the game. Start watching?",
                "Game Watcher", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (r != DialogResult.Yes) return;
            RunEngine("Watch", "-NoDevCaches", "Game Watcher");
            cWatch.Heading = "STOP WATCHER";
            cWatch.Detail = "Watching... click to stop and restore.";
            cWatch.Invalidate();
        }

        string CleanupArgs()
        {
            string a = "";
            if (!chkDevCaches.Checked) a += " -NoDevCaches";
            if (chkRecycle.Checked) a += " -EmptyRecycleBin";
            return a;
        }

        void OpenConsole()
        {
            if (scriptPath == null) return;
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\"",
                    UseShellExecute = true
                });
            }
            catch (Exception ex) { Log("Could not open console: " + ex.Message, Theme.Red); }
        }

        // ---------- Live stats ----------

        void RefreshStats()
        {
            tick++;
            try
            {
                float cpu = cpuCounter != null ? cpuCounter.NextValue() : 0;
                gCpu.Percent = cpu; gCpu.Value = cpu.ToString("0") + "%"; gCpu.Sub = Environment.ProcessorCount + " logical cores"; gCpu.Invalidate();

                double total = ci.TotalPhysicalMemory / 1048576.0, free = ci.AvailablePhysicalMemory / 1048576.0;
                double used = total - free;
                gRam.Percent = used / total * 100; gRam.Value = (used / 1024).ToString("0.0") + " / " + (total / 1024).ToString("0.0") + " GB";
                gRam.Sub = free.ToString("0") + " MB free"; gRam.Invalidate();

                var d = new DriveInfo("C");
                double dt = d.TotalSize / 1073741824.0, df = d.AvailableFreeSpace / 1073741824.0;
                gDisk.Percent = (dt - df) / dt * 100; gDisk.Value = df.ToString("0") + " GB free"; gDisk.Sub = "Drive C: of " + dt.ToString("0") + " GB"; gDisk.Invalidate();
            }
            catch { }

            string host = pingHost;
            Task.Run(() =>
            {
                long ms = -1;
                try { using (var p = new Ping()) { var r = p.Send(host, 800); if (r.Status == IPStatus.Success) ms = r.RoundtripTime; } } catch { }
                return ms;
            }).ContinueWith(t =>
            {
                if (IsDisposed) return;
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        long ms = t.Result;
                        gPing.Value = ms >= 0 ? ms + " ms" : "offline";
                        gPing.Percent = ms >= 0 ? Math.Min(100, ms / 1.5) : 100;
                        gPing.Sub = "to " + host;
                        gPing.Invalidate();
                    }));
                }
                catch { }
            });

            if (tick % 2 == 1)
            {
                Task.Run(() =>
                {
                    var procs = Process.GetProcesses();
                    var top = procs.GroupBy(p => p.ProcessName)
                        .Select(g => new { Name = g.Key, Count = g.Count(), MB = g.Sum(p => { try { return p.WorkingSet64; } catch { return 0L; } }) / 1048576 })
                        .OrderByDescending(x => x.MB).Take(9).ToList();
                    string game = procs.Select(p => p.ProcessName).FirstOrDefault(n => gameNames.Contains(n, StringComparer.OrdinalIgnoreCase));
                    foreach (var p in procs) p.Dispose();
                    return Tuple.Create(top.Select(x => new[] { x.Name, x.Count.ToString(), x.MB.ToString() }).ToList(), game);
                }).ContinueWith(t =>
                {
                    if (IsDisposed || t.IsFaulted) return;
                    try
                    {
                        BeginInvoke(new Action(() =>
                        {
                            lvTop.BeginUpdate();
                            lvTop.Items.Clear();
                            foreach (var row in t.Result.Item1) lvTop.Items.Add(new ListViewItem(new[] { row[0], row[1] + "x", row[2] + " MB" }));
                            lvTop.EndUpdate();
                            lblGame.Text = t.Result.Item2 != null ? "GAME RUNNING:  " + t.Result.Item2 : "No game running";
                            lblGame.ForeColor = t.Result.Item2 != null ? Theme.Green : Theme.Muted;
                        }));
                    }
                    catch { }
                });
            }
        }

        // ---------- Layout: header + nav ----------

        void BuildHeader()
        {
            header = new Panel { Dock = DockStyle.Top, Height = Theme.P(76), BackColor = Theme.Panel };
            var pic = new PictureBox { Size = new Size(Theme.P(46), Theme.P(46)), Location = new Point(Theme.P(20), Theme.P(15)), SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.Transparent };
            try { pic.Image = new Icon(Icon, 48, 48).ToBitmap(); } catch { }
            var title = new Label { Text = "TURBO MODE", Font = Theme.F(19f, FontStyle.Bold), ForeColor = Theme.Text, AutoSize = true, Location = new Point(Theme.P(74), Theme.P(6)), BackColor = Color.Transparent };
            var sub = new Label { Text = "v5.1  -  one-click performance booster for gaming and work", Font = Theme.F(9.5f), ForeColor = Theme.Muted, AutoSize = true, BackColor = Color.Transparent };
            sub.Location = new Point(Theme.P(77), title.Top + title.PreferredHeight - Theme.P(4));
            lblGame = new Label { Text = "No game running", Font = Theme.F(10f, FontStyle.Bold), ForeColor = Theme.Muted, AutoSize = true, Anchor = AnchorStyles.Top | AnchorStyles.Right, BackColor = Color.Transparent };
            header.Controls.AddRange(new Control[] { pic, title, sub, lblGame });
            header.Resize += delegate { lblGame.Location = new Point(header.Width - lblGame.Width - Theme.P(26), (header.Height - lblGame.Height) / 2); };
            Controls.Add(header);
        }

        void BuildNav()
        {
            var nav = new Panel { Dock = DockStyle.Left, Width = Theme.P(200), BackColor = Theme.Panel, Padding = new Padding(0, Theme.P(14), 0, 0) };
            navHelp = new NavButton("?   Help && Guide");
            navSettings = new NavButton("*   Settings");
            navHistory = new NavButton("=   Game History");
            navStartup = new NavButton(">   Startup Apps");
            navDash = new NavButton("#   Dashboard");
            nav.Controls.AddRange(new Control[] { navHelp, navSettings, navHistory, navStartup, navDash });
            navDash.Click += delegate { ShowPage(pageDash, navDash); };
            navStartup.Click += delegate { LoadStartup(); ShowPage(pageStartup, navStartup); };
            navHistory.Click += delegate { LoadHistory(); ShowPage(pageHistory, navHistory); };
            navSettings.Click += delegate { LoadConfig(); FillSettings(); ShowPage(pageSettings, navSettings); };
            navHelp.Click += delegate { ShowPage(pageHelp, navHelp); };

            var foot = new Label { Text = "Runs as Administrator\nLogs: %USERPROFILE%\\.turbomode", ForeColor = Theme.Muted, Font = Theme.F(8f), Dock = DockStyle.Bottom, Height = Theme.P(48), Padding = new Padding(Theme.P(14), 0, 0, 0) };
            nav.Controls.Add(foot);
            Controls.Add(nav);
        }

        void ShowPage(Panel page, NavButton btn)
        {
            foreach (var p in new[] { pageDash, pageStartup, pageHistory, pageSettings, pageHelp }) if (p != null) p.Visible = (p == page);
            foreach (var n in new[] { navDash, navStartup, navHistory, navSettings, navHelp }) n.SetActive(n == btn);
        }

        static Label H1(string text) { return new Label { Text = text, Font = Theme.F(15f, FontStyle.Bold), ForeColor = Theme.Text, AutoSize = true }; }
        static Label Note(string text) { return new Label { Text = text, Font = Theme.F(9.5f), ForeColor = Theme.Muted, AutoSize = true }; }

        // ---------- Dashboard ----------

        Panel BuildDashboard()
        {
            var page = new Panel { BackColor = Theme.Bg };

            var gauges = new TableLayoutPanel { Dock = DockStyle.Top, Height = Theme.P(110), ColumnCount = 4, BackColor = Theme.Bg };
            for (int i = 0; i < 4; i++) gauges.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25));
            gCpu = new Gauge { Title = "CPU", Accent = Theme.Blue, Dock = DockStyle.Fill, Margin = new Padding(0, 0, 10, 8) };
            gRam = new Gauge { Title = "Memory", Accent = Theme.Purple, Dock = DockStyle.Fill, Margin = new Padding(0, 0, 10, 8) };
            gPing = new Gauge { Title = "Ping", Accent = Theme.Green, Dock = DockStyle.Fill, Margin = new Padding(0, 0, 10, 8) };
            gDisk = new Gauge { Title = "Disk", Accent = Theme.Yellow, Dock = DockStyle.Fill, Margin = new Padding(0, 0, 0, 8) };
            gauges.Controls.Add(gCpu, 0, 0); gauges.Controls.Add(gRam, 1, 0); gauges.Controls.Add(gPing, 2, 0); gauges.Controls.Add(gDisk, 3, 0);

            var cards = new TableLayoutPanel { Dock = DockStyle.Top, Height = Theme.P(220), ColumnCount = 3, RowCount = 2, BackColor = Theme.Bg, Padding = new Padding(0, Theme.P(4), 0, 0) };
            for (int i = 0; i < 3; i++) cards.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 33.33f));
            cards.RowStyles.Add(new RowStyle(SizeType.Percent, 50)); cards.RowStyles.Add(new RowStyle(SizeType.Percent, 50));
            cGame = Card("GAME MODE", "Max FPS now: close all other apps and boost.", "\u26A1", Theme.Red);
            cWatch = Card("GAME WATCHER", WatchIdleText, "\u25CE", Theme.Orange);
            cWork = Card("WORK MODE", "Close games and bloat, keep work apps open.", "\u2692", Theme.Green);
            cClean = Card("DEEP CLEAN", "Delete junk and caches. Closes nothing.", "\u267B", Theme.Yellow);
            cRestore = Card("RESTORE", "Undo every change Turbo Mode made.", "\u21BA", Theme.Blue);
            cConsole = Card("ADVANCED", "Custom Mode: pick exactly what to close.", "\u2328", Theme.Purple);
            cGame.Click += delegate { StartGameMode(); };
            cWatch.Click += delegate { StartWatcher(); };
            cWork.Click += delegate { if (Confirm("WORK MODE closes games, media players and bloat apps.\nYour browser, IDE and chat apps stay open.\n\nContinue?")) RunEngine("Work", CleanupArgs(), "Work Mode"); };
            cClean.Click += delegate { RunEngine("Clean", CleanupArgs(), "Deep Clean"); };
            cRestore.Click += delegate { RunEngine("Restore", "", "Restore"); };
            cConsole.Click += delegate { OpenConsole(); };
            cards.Controls.Add(cGame, 0, 0); cards.Controls.Add(cWatch, 1, 0); cards.Controls.Add(cWork, 2, 0);
            cards.Controls.Add(cClean, 0, 1); cards.Controls.Add(cRestore, 1, 1); cards.Controls.Add(cConsole, 2, 1);

            var opts = new FlowLayoutPanel { Dock = DockStyle.Top, Height = Theme.P(32), BackColor = Theme.Bg, Padding = new Padding(0, Theme.P(4), 0, 0) };
            chkDevCaches = new CheckBox { Text = "Also clear developer caches (npm, pip, yarn, NuGet)", Checked = true, ForeColor = Theme.Muted, AutoSize = true, Margin = new Padding(0, 0, 24, 0) };
            chkRecycle = new CheckBox { Text = "Also empty the Recycle Bin (permanent!)", Checked = false, ForeColor = Theme.Muted, AutoSize = true };
            opts.Controls.Add(chkDevCaches); opts.Controls.Add(chkRecycle);

            var statusBar = new Panel { Dock = DockStyle.Top, Height = Theme.P(34), BackColor = Theme.Bg };
            lblStatus = new Label { Text = "Ready", ForeColor = Theme.Text, Font = Theme.F(10f, FontStyle.Bold), AutoSize = true, Location = new Point(0, Theme.P(8)) };
            busy = new ProgressBar { Style = ProgressBarStyle.Marquee, Width = Theme.P(160), Height = Theme.P(8), Visible = false, Anchor = AnchorStyles.Top | AnchorStyles.Right };
            statusBar.Controls.Add(lblStatus); statusBar.Controls.Add(busy);
            statusBar.Resize += delegate { busy.Location = new Point(statusBar.Width - busy.Width, Theme.P(14)); };

            var bottom = new SplitContainer { Dock = DockStyle.Fill, BackColor = Theme.Bg, SplitterWidth = Theme.P(10), FixedPanel = FixedPanel.Panel2 };
            log = new RichTextBox { Dock = DockStyle.Fill, BackColor = Color.FromArgb(10, 12, 16), ForeColor = Theme.Text, BorderStyle = BorderStyle.None, ReadOnly = true, Font = new Font("Cascadia Mono", 9f), WordWrap = true, ScrollBars = RichTextBoxScrollBars.Vertical };
            if (log.Font.Name != "Cascadia Mono") log.Font = new Font("Consolas", 9.5f);
            var logWrap = new Panel { Dock = DockStyle.Fill, Padding = new Padding(Theme.P(10)), BackColor = Color.FromArgb(10, 12, 16) };
            logWrap.Controls.Add(log);
            bottom.Panel1.Controls.Add(logWrap);

            lvTop = MakeList(new[] { "Top apps (RAM)", "#", "MB" }, new[] { 150, 36, 60 });
            lvTop.Dock = DockStyle.Fill;
            lvTop.HeaderStyle = ColumnHeaderStyle.None;
            var topTitle = new Label { Text = "TOP APPS BY MEMORY", Dock = DockStyle.Top, Height = Theme.P(30), Font = Theme.F(8.5f, FontStyle.Bold), ForeColor = Theme.Muted, BackColor = Theme.Card, Padding = new Padding(Theme.P(6), Theme.P(8), 0, 0) };
            bottom.Panel2.Controls.Add(lvTop);
            bottom.Panel2.Controls.Add(topTitle);
            bottom.Panel2.BackColor = Theme.Card;
            page.Resize += delegate { try { bottom.SplitterDistance = Math.Max(Theme.P(200), bottom.Width - Theme.P(270)); } catch { } };

            page.Controls.Add(bottom);
            page.Controls.Add(statusBar);
            page.Controls.Add(opts);
            page.Controls.Add(cards);
            page.Controls.Add(gauges);
            return page;
        }

        ActionCard Card(string h, string d, string glyph, Color c)
        {
            return new ActionCard { Heading = h, Detail = d, Glyph = glyph, Accent = c, Dock = DockStyle.Fill, Margin = new Padding(0, 0, Theme.P(10), Theme.P(10)) };
        }

        bool Confirm(string msg)
        {
            return MessageBox.Show(this, msg, "TURBO MODE", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;
        }

        ListView MakeList(string[] cols, int[] widths)
        {
            var lv = new ListView { View = View.Details, FullRowSelect = true, BackColor = Theme.Card, ForeColor = Theme.Text, BorderStyle = BorderStyle.None, HeaderStyle = ColumnHeaderStyle.Nonclickable, Font = Theme.F(9.5f) };
            for (int i = 0; i < cols.Length; i++) lv.Columns.Add(cols[i], Theme.P(widths[i]));
            return lv;
        }

        void Log(string text, Color color)
        {
            if (log == null) return;
            log.SelectionStart = log.TextLength;
            log.SelectionLength = 0;
            log.SelectionColor = color;
            log.AppendText(text + "\n");
            log.SelectionColor = log.ForeColor;
            log.ScrollToCaret();
        }

        // ---------- Startup apps ----------

        Panel BuildStartupPage()
        {
            var page = new Panel { BackColor = Theme.Bg };
            var top = new Panel { Dock = DockStyle.Top, Height = Theme.P(90) };
            var h = H1("Startup Apps"); h.Location = new Point(0, 0);
            var n = Note("Tick = starts with Windows. Untick to stop an app launching at boot (faster startup).\nThis is the same switch Task Manager uses - you can turn it back on any time."); n.Location = new Point(2, Theme.P(36));
            var refresh = FlatBtn("Refresh", Theme.Blue); refresh.Anchor = AnchorStyles.Top | AnchorStyles.Right; refresh.Click += delegate { LoadStartup(); };
            top.Controls.AddRange(new Control[] { h, n, refresh });
            top.Resize += delegate { refresh.Location = new Point(top.Width - refresh.Width, Theme.P(6)); };

            lvStartup = MakeList(new[] { "App", "Status", "Command", "Location" }, new[] { 230, 90, 470, 120 });
            lvStartup.CheckBoxes = true;
            lvStartup.Dock = DockStyle.Fill;
            lvStartup.ItemChecked += OnStartupChecked;
            page.Controls.Add(lvStartup);
            page.Controls.Add(top);
            return page;
        }

        Button FlatBtn(string text, Color accent)
        {
            var b = new Button { Text = text, FlatStyle = FlatStyle.Flat, BackColor = accent, ForeColor = Color.White, Font = Theme.F(9.5f, FontStyle.Bold), Size = new Size(Theme.P(130), Theme.P(36)), Cursor = Cursors.Hand };
            b.FlatAppearance.BorderSize = 0;
            return b;
        }

        List<StartupEntry> ReadStartupEntries()
        {
            const string approved = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\";
            var list = new List<StartupEntry>();
            var sources = new[]
            {
                Tuple.Create(Registry.CurrentUser,  @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", approved + "Run", "User"),
                Tuple.Create(Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run", approved + "Run", "All users"),
                Tuple.Create(Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run", approved + "Run32", "All users (32-bit)")
            };
            foreach (var s in sources)
            {
                try
                {
                    using (var k = s.Item1.OpenSubKey(s.Item2))
                    {
                        if (k == null) continue;
                        foreach (var name in k.GetValueNames())
                            list.Add(new StartupEntry { Name = name, Command = Convert.ToString(k.GetValue(name)), Root = s.Item1, ApprovedPath = s.Item3, Location = s.Item4 });
                    }
                }
                catch { }
            }
            var folders = new[]
            {
                Tuple.Create(Environment.GetFolderPath(Environment.SpecialFolder.Startup), Registry.CurrentUser, "Startup folder"),
                Tuple.Create(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup), Registry.LocalMachine, "Startup folder (all)")
            };
            foreach (var f in folders)
            {
                try
                {
                    foreach (var file in Directory.GetFiles(f.Item1))
                    {
                        string nm = Path.GetFileName(file);
                        if (nm.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)) continue;
                        list.Add(new StartupEntry { Name = nm, Command = file, Root = f.Item2, ApprovedPath = approved + "StartupFolder", Location = f.Item3 });
                    }
                }
                catch { }
            }
            foreach (var e in list)
            {
                e.Enabled = true;
                try
                {
                    using (var k = e.Root.OpenSubKey(e.ApprovedPath))
                    {
                        var v = k == null ? null : k.GetValue(e.Name) as byte[];
                        if (v != null && v.Length > 0) e.Enabled = v[0] % 2 == 0;   // 2/6 = on, 3/7 = off
                    }
                }
                catch { }
            }
            return list;
        }

        void LoadStartup()
        {
            loadingStartup = true;
            lvStartup.BeginUpdate();
            lvStartup.Items.Clear();
            foreach (var e in ReadStartupEntries())
            {
                var it = new ListViewItem(new[] { e.Name, e.Enabled ? "On" : "Off", e.Command, e.Location }) { Checked = e.Enabled, Tag = e };
                it.ForeColor = e.Enabled ? Theme.Text : Theme.Muted;
                lvStartup.Items.Add(it);
            }
            lvStartup.EndUpdate();
            loadingStartup = false;
        }

        void OnStartupChecked(object sender, ItemCheckedEventArgs ev)
        {
            if (loadingStartup) return;
            var e = (StartupEntry)ev.Item.Tag;
            bool enable = ev.Item.Checked;
            // WinForms replays initial check states when the list's window is created -
            // only a real change of state may ever touch the registry
            if (enable == e.Enabled) return;
            try
            {
                using (var k = e.Root.CreateSubKey(e.ApprovedPath))
                    k.SetValue(e.Name, new byte[] { (byte)(enable ? 2 : 3), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, RegistryValueKind.Binary);
                e.Enabled = enable;
                ev.Item.SubItems[1].Text = enable ? "On" : "Off";
                ev.Item.ForeColor = enable ? Theme.Text : Theme.Muted;
                Log("Startup: " + e.Name + (enable ? " enabled" : " disabled"), Theme.Green);
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Could not change " + e.Name + ":\n" + ex.Message, "Startup Apps", MessageBoxButtons.OK, MessageBoxIcon.Error);
                loadingStartup = true; ev.Item.Checked = !enable; loadingStartup = false;
            }
        }

        // ---------- History ----------

        Panel BuildHistoryPage()
        {
            var page = new Panel { BackColor = Theme.Bg };
            var top = new Panel { Dock = DockStyle.Top, Height = Theme.P(72) };
            var h = H1("Game History"); h.Location = new Point(0, 0);
            var n = Note("Every Game Watcher session is recorded here: how long you played, RAM freed and your ping."); n.Location = new Point(2, Theme.P(36));
            top.Controls.AddRange(new Control[] { h, n });
            lvHistory = MakeList(new[] { "Date", "Game", "Minutes", "RAM freed", "Lowest free RAM", "Avg ping", "Max ping", "Apps re-closed" }, new[] { 140, 230, 80, 90, 120, 80, 80, 110 });
            lvHistory.Dock = DockStyle.Fill;
            page.Controls.Add(lvHistory);
            page.Controls.Add(top);
            return page;
        }

        void LoadHistory()
        {
            if (lvHistory == null) return;
            lvHistory.BeginUpdate();
            lvHistory.Items.Clear();
            string file = Path.Combine(turboDir, "history.csv");
            if (File.Exists(file))
            {
                var lines = File.ReadAllLines(file).Skip(1).Reverse();
                foreach (var line in lines)
                {
                    var f = line.Trim().Trim('"').Split(new[] { "\",\"" }, StringSplitOptions.None);
                    if (f.Length < 8) continue;
                    lvHistory.Items.Add(new ListViewItem(new[] { f[0], f[1], f[2], f[3] + " MB", f[4] + " MB", f[5] == "-1" ? "--" : f[5] + " ms", f[6] == "-1" ? "--" : f[6] + " ms", f[7] }));
                }
            }
            if (lvHistory.Items.Count == 0) lvHistory.Items.Add(new ListViewItem(new[] { "No sessions yet", "Use GAME WATCHER on the Dashboard", "", "", "", "", "", "" }) { ForeColor = Theme.Muted });
            lvHistory.EndUpdate();
        }

        // ---------- Settings ----------

        string ConfigPath { get { return Path.Combine(turboDir, "config.json"); } }

        void LoadConfig()
        {
            gameNames = new[] { "VALORANT-Win64-Shipping", "cs2", "FortniteClient-Win64-Shipping", "r5apex", "GTA5", "TslGame", "HD-Player", "AndroidEmulatorEn", "AndroidEmulatorEx" };
            try
            {
                if (!File.Exists(ConfigPath)) return;
                var d = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(ConfigPath));
                gameNames = ToList(d, "GameProcesses").ToArray();
                object ph;
                if (d.TryGetValue("PingHost", out ph) && ph != null && Convert.ToString(ph).Length > 0) pingHost = Convert.ToString(ph);
            }
            catch { }
        }

        static List<string> ToList(Dictionary<string, object> d, string key)
        {
            var r = new List<string>();
            object v;
            if (d.TryGetValue(key, out v) && v is IEnumerable && !(v is string))
                foreach (var x in (IEnumerable)v) if (x != null) r.Add(x.ToString());
            return r;
        }

        Panel BuildSettingsPage()
        {
            var page = new Panel { BackColor = Theme.Bg, AutoScroll = true };
            var h = H1("Settings"); h.Location = new Point(0, 0);
            var n = Note("One name per line. Use the process name from Task Manager > Details, without \".exe\"."); n.Location = new Point(2, Theme.P(36));
            page.Controls.AddRange(new Control[] { h, n });

            int y = Theme.P(72);
            txtGames = SettingBox(page, "Games to boost (Game Watcher + Game Mode)", ref y, Theme.P(130));
            txtGameKeep = SettingBox(page, "Never close these apps during Game Mode (e.g. Discord)", ref y, Theme.P(80));
            txtWorkKeep = SettingBox(page, "Extra apps to keep open in Work Mode", ref y, Theme.P(60));

            var l1 = Note("Ping server (pick one near your game region)"); l1.Location = new Point(2, y); page.Controls.Add(l1);
            txtPingHost = new TextBox { Location = new Point(2, y + Theme.P(24)), Width = Theme.P(260), BackColor = Theme.Card, ForeColor = Theme.Text, BorderStyle = BorderStyle.FixedSingle };
            page.Controls.Add(txtPingHost);
            var l2 = Note("Re-close background apps every (seconds)"); l2.Location = new Point(Theme.P(300), y); page.Controls.Add(l2);
            numInterval = new NumericUpDown { Location = new Point(Theme.P(302), y + Theme.P(24)), Width = Theme.P(80), Minimum = 5, Maximum = 300, BackColor = Theme.Card, ForeColor = Theme.Text };
            page.Controls.Add(numInterval);
            y += Theme.P(76);

            var save = FlatBtn("Save", Theme.Green); save.Location = new Point(2, y);
            var folder = FlatBtn("Open data folder", Theme.CardHi); folder.Width = Theme.P(170); folder.Location = new Point(Theme.P(144), y);
            save.Click += delegate { SaveSettings(); };
            folder.Click += delegate { Process.Start("explorer.exe", "\"" + turboDir + "\""); };
            page.Controls.Add(save); page.Controls.Add(folder);
            FillSettings();
            return page;
        }

        TextBox SettingBox(Panel page, string label, ref int y, int height)
        {
            var l = Note(label); l.Location = new Point(2, y); page.Controls.Add(l);
            var t = new TextBox { Multiline = true, ScrollBars = ScrollBars.Vertical, Location = new Point(2, y + Theme.P(24)), Size = new Size(Theme.P(580), height), BackColor = Theme.Card, ForeColor = Theme.Text, BorderStyle = BorderStyle.FixedSingle, Font = new Font("Consolas", 10f) };
            page.Controls.Add(t);
            y += height + Theme.P(40);
            return t;
        }

        void FillSettings()
        {
            var d = new Dictionary<string, object>();
            try { if (File.Exists(ConfigPath)) d = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(ConfigPath)); } catch { }
            txtGames.Text = string.Join("\r\n", ToList(d, "GameProcesses").Count > 0 ? ToList(d, "GameProcesses") : gameNames.ToList());
            txtGameKeep.Text = string.Join("\r\n", ToList(d, "ExtraGameKeep"));
            txtWorkKeep.Text = string.Join("\r\n", ToList(d, "ExtraWorkKeep"));
            txtPingHost.Text = pingHost;
            object iv; int interval = 15;
            if (d.TryGetValue("WatcherIntervalSec", out iv)) { try { interval = Convert.ToInt32(iv); } catch { } }
            numInterval.Value = Math.Max(5, Math.Min(300, interval));
        }

        static string[] Lines(TextBox t)
        {
            return t.Lines.Select(s => s.Trim()).Where(s => s.Length > 0).Select(s => s.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? s.Substring(0, s.Length - 4) : s).Distinct().ToArray();
        }

        void SaveSettings()
        {
            var d = new Dictionary<string, object>
            {
                { "GameProcesses", Lines(txtGames) },
                { "ExtraGameKeep", Lines(txtGameKeep) },
                { "ExtraWorkKeep", Lines(txtWorkKeep) },
                { "WatcherIntervalSec", (int)numInterval.Value },
                { "PingHost", string.IsNullOrWhiteSpace(txtPingHost.Text) ? "1.1.1.1" : txtPingHost.Text.Trim() }
            };
            try
            {
                File.WriteAllText(ConfigPath, new JavaScriptSerializer().Serialize(d), new UTF8Encoding(false));
                LoadConfig();
                MessageBox.Show(this, "Settings saved.", "TURBO MODE", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex) { MessageBox.Show(this, "Could not save: " + ex.Message, "TURBO MODE", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }

        // ---------- Help ----------

        Panel BuildHelpPage()
        {
            var page = new Panel { BackColor = Theme.Bg };
            var rtb = new RichTextBox { Dock = DockStyle.Fill, BackColor = Theme.Bg, ForeColor = Theme.Text, BorderStyle = BorderStyle.None, ReadOnly = true, Font = Theme.F(10.5f) };
            page.Controls.Add(rtb);

            Action<string> h = s => { rtb.SelectionFont = Theme.F(14f, FontStyle.Bold); rtb.SelectionColor = Theme.Text; rtb.AppendText("\n" + s + "\n"); };
            Action<string, string> item = (title, body) =>
            {
                rtb.SelectionFont = Theme.F(10.5f, FontStyle.Bold); rtb.SelectionColor = Theme.Yellow; rtb.AppendText("  " + title + "\n");
                rtb.SelectionFont = Theme.F(10.5f); rtb.SelectionColor = Theme.Muted; rtb.AppendText("     " + body.Replace("\n", "\n     ") + "\n\n");
            };

            rtb.SelectionFont = Theme.F(20f, FontStyle.Bold); rtb.SelectionColor = Theme.Red; rtb.AppendText("How to use TURBO MODE\n");
            rtb.SelectionFont = Theme.F(10.5f); rtb.SelectionColor = Theme.Muted;
            rtb.AppendText("Turbo Mode frees up memory and CPU so your games and work run smoother. Everything is one click,\nand everything it changes can be undone with RESTORE.\n");

            h("Quick start - gaming");
            item("1.  Save your work", "Game Mode and Game Watcher close other apps. Anything unsaved in those apps is lost.");
            item("2.  Click GAME WATCHER", "The status bar shows \"Waiting for a game to launch...\".");
            item("3.  Launch your game", "Turbo Mode detects it, frees RAM, switches to max performance and shows live RAM / CPU / ping.");
            item("4.  Play, then quit the game", "Everything is restored automatically and the session appears in Game History.");

            h("What each button does");
            item("GAME MODE", "Instant boost: closes all apps except your game and anti-cheat, frees RAM, sets the\nhigh-performance power plan and raises your game's priority if it is already running.");
            item("GAME WATCHER", "Same boost, but automatic. While you play it re-closes background apps that restart themselves\n(Slack tray, Edge WebView, updaters). Apps you open yourself (e.g. Discord) are left alone.\nClick STOP WATCHER at any time to stop and restore.");
            item("WORK MODE", "Closes only games, media players and bloat. Your browser, code editor, Slack, Teams and Docker stay open.");
            item("DEEP CLEAN", "Deletes temp files, browser caches, Windows Update leftovers, crash dumps and shader cache.\nWith the checkbox on it also clears npm / pip / yarn / NuGet caches (they re-download when needed).\nNo apps are closed.");
            item("RESTORE", "Restarts the Windows services Turbo Mode stopped, switches back to your original power plan and\nresets network tweaks. Use it any time something feels off.");
            item("ADVANCED", "Opens the classic console version with Custom Mode, where you pick exactly which apps to close,\nand can save selections as profiles.");

            h("Other tabs");
            item("Startup Apps", "Untick apps you don't need at boot to make Windows start faster. Tick again to undo.");
            item("Game History", "Every Game Watcher session: date, game, minutes played, RAM freed and ping.");
            item("Settings", "Add your games (Task Manager > Details tab shows the exact process name), apps that must never be\nclosed, your ping server and how often background apps are re-closed.");

            h("Is it safe?");
            item("Never touches Windows itself", "Only apps in your own session are closed. Windows services, drivers, antivirus and anti-cheat\nare never touched.");
            item("Everything is reversible", "RESTORE undoes services, power plan and network tweaks. Startup changes can be ticked back on.");
            item("Recycle Bin", "Only emptied if you tick that box - files deleted from the Recycle Bin cannot be recovered.");
            item("Logs", "Every action is logged in %USERPROFILE%\\.turbomode\\turbomode.log");

            h("Troubleshooting");
            item("\"Windows protected your PC\"", "Click More info > Run anyway. The app is unsigned because it is built from source.");
            item("Admin prompt", "Turbo Mode needs Administrator rights to stop services and change the power plan. Click Yes.");
            item("\"Anti-cheat blocked priority change\"", "Normal for games like Valorant - the rest of the boost still works.");
            item("My game isn't detected", "Add its process name in Settings > Games to boost, then Save.");
            rtb.SelectionStart = 0;
            rtb.ScrollToCaret();
            return page;
        }

        // ---------- Closing ----------

        void OnClosingForm(object sender, FormClosingEventArgs e)
        {
            if (!IsBusy) return;
            if (runningMode == "Game Watcher")
            {
                var r = MessageBox.Show(this, "Game Watcher is running.\n\nStop it and restore normal settings before closing?", "TURBO MODE", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (r == DialogResult.Cancel) { e.Cancel = true; return; }
                if (r == DialogResult.Yes)
                {
                    File.WriteAllText(Path.Combine(turboDir, "stop.flag"), "stop");
                    running.WaitForExit(20000);
                }
            }
            else
            {
                var r = MessageBox.Show(this, "\"" + runningMode + "\" is still running. Let it finish in the background?", "TURBO MODE", MessageBoxButtons.OKCancel, MessageBoxIcon.Question);
                if (r == DialogResult.Cancel) e.Cancel = true;
            }
        }
    }

    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { SetProcessDPIAware(); } catch { }
            try { using (var g = Graphics.FromHwnd(IntPtr.Zero)) Theme.Scale = g.DpiX / 96f; } catch { }
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (s, e) => Crash(e.Exception);
            try { Application.Run(new MainForm(args)); }
            catch (Exception ex) { Crash(ex); }
        }

        static void Crash(Exception ex)
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".turbomode");
            string file = Path.Combine(dir, "crash.log");
            try { Directory.CreateDirectory(dir); File.AppendAllText(file, "[" + DateTime.Now + "]\r\n" + ex + "\r\n\r\n"); } catch { }
            MessageBox.Show("Something went wrong:\n\n" + ex.Message + "\n\nDetails were saved to:\n" + file, "TURBO MODE", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();
    }
}
