// SPDX-License-Identifier: GPL-3.0-or-later
// Uses Windows' installed .NET Framework; no browser or extra UI runtime required.
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

class InternalSetup {
    internal static string Scratch, Payload, Bootstrap, Hash;
    internal static bool Prepared;
    internal static void Prepare() {
        Directory.CreateDirectory(Scratch);
        Payload = Path.Combine(Scratch, "payload.zip"); Bootstrap = Path.Combine(Scratch, "Bootstrap-InternalSetup.ps1");
        foreach (string name in new [] { "Payload", "Bootstrap" }) {
            using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            using (FileStream output = new FileStream(name == "Payload" ? Payload : Bootstrap, FileMode.Create)) { input.CopyTo(output); }
        }
        using (StreamReader reader = new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream("Checksum"))) { Hash = reader.ReadToEnd().Trim(); }
        using (SHA256 sha = SHA256.Create())
        using (FileStream input = File.OpenRead(Payload)) {
            if (!String.Equals(Hash, BitConverter.ToString(sha.ComputeHash(input)).Replace("-", ""), StringComparison.OrdinalIgnoreCase)) { throw new Exception("Setup file is damaged. Download a fresh copy and try again."); }
        }
        Prepared = true;
    }
    [STAThread]
    static int Main(string[] args) {
        Scratch = Path.Combine(Path.GetTempPath(), "neuralDoom-setup-" + Guid.NewGuid().ToString("N"));
        try {
            if (args.Length == 1 && args[0] == "--verify") { Prepare(); return 0; }
            if (args.Length != 0 && !(args.Length == 2 && args[0] == "--preview")) { return 2; }
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            using (SetupWindow window = new SetupWindow()) {
                if (args.Length == 2) { window.Preview(args[1]); return 0; }
                Application.Run(window);
            }
            return 0;
        } catch (Exception error) {
            if (args.Length == 0) { MessageBox.Show(error.Message, "neuralDoom Setup", MessageBoxButtons.OK, MessageBoxIcon.Error); }
            return 1;
        } finally {
            string prefix = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (Path.GetFullPath(Scratch).StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && Directory.Exists(Scratch)) { try { Directory.Delete(Scratch, true); } catch {} }
        }
    }
}

class SetupWindow : Form {
    readonly Color background = Color.FromArgb(19, 22, 27), panelColor = Color.FromArgb(28, 32, 39), ink = Color.FromArgb(240, 239, 236), muted = Color.FromArgb(158, 167, 181), accent = Color.FromArgb(232, 74, 58);
    Panel content, sidebar;
    Button next, back, cancel;
    TextBox destination, game, details;
    CheckBox shortcut;
    Label status, transfer;
    ProgressBar progress;
    int page;
    bool running, cancelRequested, showDetails, restartRequired;
    string installPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "neuralDoom", "Internal"), gamePath = "", logPath, cancelPath;
    bool desktopShortcut = true;
    readonly StringBuilder log = new StringBuilder();

    public SetupWindow() {
        Text = "neuralDoom Setup"; ClientSize = new Size(920, 630); MinimumSize = new Size(940, 670);
        StartPosition = FormStartPosition.CenterScreen; BackColor = background; ForeColor = ink;
        Font = new Font("Segoe UI", 10); AutoScaleMode = AutoScaleMode.Font; MaximizeBox = false;
        sidebar = new Panel { Dock = DockStyle.Left, Width = 226, BackColor = Color.FromArgb(13, 15, 19) };
        sidebar.Paint += DrawSidebar; Controls.Add(sidebar);
        Panel footer = new Panel { Dock = DockStyle.Bottom, Height = 76, BackColor = panelColor };
        Controls.Add(footer);
        next = MakeButton("Next", 0, 18, 140, true); next.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        back = MakeButton("Back", 0, 18, 90, false); back.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        cancel = MakeButton("Cancel", 22, 18, 95, false);
        footer.Controls.AddRange(new Control[] { next, back, cancel });
        footer.Resize += delegate { next.Left = footer.Width - 164; back.Left = footer.Width - 266; };
        next.Left = footer.Width - 164; back.Left = footer.Width - 266;
        content = new Panel { Dock = DockStyle.Fill, Padding = new Padding(32), AutoScroll = true };
        Controls.Add(content); content.BringToFront();
        next.Click += async delegate { if (page == 2 || page == 5) { await Install(); } else if (page == 4) { Close(); } else if (page == 1) { if (ValidateChoices()) ShowPage(2); } else ShowPage(1); };
        back.Click += delegate { ShowPage(page == 5 ? 1 : Math.Max(0, page - 1)); };
        cancel.Click += delegate { Close(); };
        FormClosing += delegate(object sender, FormClosingEventArgs e) {
            if (!running) return;
            e.Cancel = true;
            if (cancelRequested) return;
            if (MessageBox.Show(this, "Stop after the current operation? Verified downloads will be kept so you can retry.", "Cancel setup", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes) {
                cancelRequested = true; File.WriteAllText(cancelPath, "cancel"); cancel.Enabled = false;
                status.Text = "Stopping after the current operation...";
            }
        };
        using (Stream version = Assembly.GetExecutingAssembly().GetManifestResourceStream("Version")) {
            if (version != null) using (StreamReader reader = new StreamReader(version)) installPath = Path.Combine(installPath, reader.ReadToEnd().Trim());
        }
        gamePath = FindBFG(); ShowPage(0);
    }
    Button MakeButton(string text, int x, int y, int width, bool primary) {
        Button b = new Button { Text = text, Location = new Point(x, y), Size = new Size(width, 40), FlatStyle = FlatStyle.Flat, BackColor = primary ? accent : panelColor, ForeColor = ink, Cursor = Cursors.Hand };
        b.FlatAppearance.BorderSize = primary ? 0 : 1; b.FlatAppearance.BorderColor = Color.FromArgb(63, 69, 80); return b;
    }
    Label TextAt(string text, int y, int height, float size, Color color) {
        Label label = new Label { Text = text, Location = new Point(32, y), Size = new Size(594, height), ForeColor = color, Font = new Font("Segoe UI", size), AutoEllipsis = true };
        content.Controls.Add(label); return label;
    }
    TextBox PathField(string value, int y, bool ownedGame) {
        TextBox field = new TextBox { Text = value, Location = new Point(32, y), Size = new Size(472, 30), BackColor = panelColor, ForeColor = ink, BorderStyle = BorderStyle.FixedSingle };
        Button browse = MakeButton("Browse...", 516, y - 5, 110, false);
        browse.Click += delegate {
            using (FolderBrowserDialog picker = new FolderBrowserDialog()) {
                picker.Description = ownedGame ? "Select your owned Doom 3 BFG Edition folder" : "Choose or create an empty installation folder";
                picker.ShowNewFolderButton = !ownedGame; if (Directory.Exists(field.Text)) picker.SelectedPath = field.Text;
                if (picker.ShowDialog(this) == DialogResult.OK) field.Text = picker.SelectedPath;
            }
        };
        content.Controls.Add(field); content.Controls.Add(browse); return field;
    }
    void DrawSidebar(object sender, PaintEventArgs e) {
        Graphics g = e.Graphics;
        using (Pen line = new Pen(Color.FromArgb(46, 32, 34), 2)) { for (int i = 0; i < 8; i++) g.DrawLine(line, -50, 330 + i * 32, 260, 160 + i * 32); }
        using (Font title = new Font("Segoe UI", 24, FontStyle.Bold)) g.DrawString("neural\nDOOM", title, Brushes.White, 23, 34);
        using (Brush red = new SolidBrush(accent)) g.FillRectangle(red, 26, 146, 40, 4);
        string[] steps = { "01   Welcome", "02   Install location", "03   Ready to install", "04   Installation", "05   Complete" };
        int active = page == 5 ? 3 : page;
        for (int i = 0; i < steps.Length; i++) using (Brush brush = new SolidBrush(i == active ? ink : muted)) {
            using (Font font = new Font("Segoe UI", 10, i == active ? FontStyle.Bold : FontStyle.Regular)) g.DrawString(steps[i], font, brush, 26, 208 + 42 * i);
        }
        using (Brush brush = new SolidBrush(muted))
        using (Font font = new Font("Segoe UI", 8)) g.DrawString("NATIVE RTX EDITION\nINTERNAL TEST BUILD", font, brush, 26, sidebar.Height - 66);
    }
    void ShowPage(int value) {
        page = value; while (content.Controls.Count > 0) content.Controls[0].Dispose(); sidebar.Invalidate();
        back.Visible = value == 1 || value == 2 || value == 5; back.Enabled = !running;
        next.Visible = value != 3; next.Text = value == 2 ? "Install" : value == 4 ? "Finish" : value == 5 ? "Retry" : "Next";
        cancel.Visible = value != 4; cancel.Enabled = true; AcceptButton = next.Visible ? next : null;
        if (value == 0) {
            TextAt("A darker world.\nA new light.", 38, 116, 32, ink);
            TextAt("Welcome to neuralDoom", 181, 38, 19, ink);
            TextAt("Doom 3 atmosphere, with ray-traced lighting, material reflections, HDR and ultrawide support.", 233, 64, 12, muted);
            TextAt("Setup takes care of the downloads, supporting files and configuration. All you need is your installed copy of Doom 3 BFG Edition.", 320, 76, 11, muted);
            TextAt("About 1.65 GB to download  /  Allow 15 GB of free space", 431, 44, 10, ink);
        } else if (value == 1) {
            TextAt("Make room for DOOM.", 34, 48, 25, ink);
            TextAt("Choose where to install. Your original game stays in place.", 96, 44, 11, muted);
            TextAt("Install neuralDoom to", 164, 30, 11, ink); destination = PathField(installPath, 200, false);
            TextAt("Doom 3 BFG Edition game folder", 266, 30, 11, ink); game = PathField(gamePath, 304, true);
            TextAt(String.IsNullOrEmpty(gamePath) ? "Select the folder containing your owned BFG installation." : "BFG detected. You can select another copy if needed.", 346, 48, 10, muted);
            shortcut = new CheckBox { Text = "Create a desktop shortcut", Checked = desktopShortcut, ForeColor = ink, Location = new Point(32, 426), Size = new Size(350, 30) }; content.Controls.Add(shortcut);
        } else if (value == 2) {
            TextAt("Ready when you are.", 34, 54, 25, ink);
            TextAt("INSTALL LOCATION", 120, 28, 9, muted); TextAt(installPath, 150, 68, 11, ink);
            TextAt("GAME DATA SOURCE", 232, 28, 9, muted); TextAt(gamePath, 262, 68, 11, ink);
            TextAt("Setup will download and verify the lighting data, install Microsoft prerequisites if needed, and prepare your game.", 351, 70, 11, muted);
            TextAt("Windows may request permission for Microsoft prerequisites.\nThe game will not launch automatically.", 443, 52, 10, ink);
        } else if (value == 3) {
            TextAt("Building your experience.", 34, 56, 24, ink);
            status = TextAt("Verifying setup files...", 140, 68, 14, ink);
            progress = new ProgressBar { Location = new Point(32, 228), Size = new Size(594, 9), Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 30 }; content.Controls.Add(progress);
            transfer = TextAt("This can take a few minutes. You can leave setup running.", 257, 56, 10, muted);
            Button toggle = MakeButton("Show details", 32, 330, 132, false); content.Controls.Add(toggle);
            details = new TextBox { Location = new Point(32, 384), Size = new Size(594, 130), Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, BackColor = panelColor, ForeColor = muted, Visible = showDetails };
            details.Text = log.ToString(); content.Controls.Add(details);
            toggle.Click += delegate { showDetails = !showDetails; details.Visible = showDetails; toggle.Text = showDetails ? "Hide details" : "Show details"; };
        } else {
            bool success = value == 4;
            TextAt(success ? "Welcome back to Mars." : cancelRequested ? "Setup paused." : "Let's get this sorted.", 34, 72, 25, ink);
            TextAt(success ? (restartRequired ? "Installation is complete. Restart Windows before playing." : "Installation complete. Your game is ready.") : cancelRequested ? "Setup stopped safely. You can retry using the verified files already downloaded." : "Setup couldn't finish. Your log has the details; you can retry after resolving the issue.", 138, 92, 12, muted);
            TextAt(success ? "Use the Start menu or your desktop shortcut to start.\nF3 reflections  ·  F4 bounce  ·  F7 AO  ·  F8 contact shadows\nF11 compares all four lighting effects together." : "Your original BFG installation has not been changed.", 259, 106, 11, ink);
            Button folder = MakeButton("Open install folder", 32, 402, 185, false); content.Controls.Add(folder);
            folder.Click += delegate { if (Directory.Exists(installPath)) Process.Start(new ProcessStartInfo(installPath) { UseShellExecute = true }); };
            Button logs = MakeButton("View setup log", 233, 402, 165, false); content.Controls.Add(logs);
            logs.Click += delegate { if (File.Exists(logPath)) Process.Start(new ProcessStartInfo("notepad.exe", Quote(logPath)) { UseShellExecute = false }); };
            if (success) { Button guide = MakeButton("Test controls", 414, 402, 160, false); content.Controls.Add(guide); guide.Click += delegate { Process.Start(new ProcessStartInfo("notepad.exe", Quote(Path.Combine(installPath, "INTERNAL_TESTING.md"))) { UseShellExecute = false }); }; }
        }
    }
    bool ValidateChoices() {
        try {
            installPath = Path.GetFullPath(destination.Text.Trim()); gamePath = Path.GetFullPath(game.Text.Trim()); desktopShortcut = shortcut.Checked;
            if (!File.Exists(Path.Combine(gamePath, "base", "maps", "mars_city2.resources"))) throw new Exception("Select Doom 3 BFG Edition's installed folder, containing base. The original Doom 3 edition is not supported.");
            if (String.Equals(installPath.TrimEnd('\\'), gamePath.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase) || installPath.StartsWith(gamePath.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase) || gamePath.StartsWith(installPath.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) throw new Exception("Choose a separate folder for neuralDoom, outside your owned game installation.");
            if (Directory.Exists(installPath) && Directory.GetFileSystemEntries(installPath).Length > 0 && !File.Exists(Path.Combine(installPath, "internal-package.json"))) throw new Exception("Choose an empty folder. Setup preserves unrelated files.");
            string root = Path.GetPathRoot(installPath);
            if (new DriveInfo(root).AvailableFreeSpace < 15L * 1024 * 1024 * 1024) throw new Exception("Please allow at least 15 GB of free space on the installation drive.");
            return true;
        } catch (Exception error) { MessageBox.Show(this, error.Message, "Check your folders", MessageBoxButtons.OK, MessageBoxIcon.Information); return false; }
    }
    internal static string Quote(string value) { return "\"" + value.Replace("\"", "") .TrimEnd('\\') + "\""; }
    async Task Install() {
        running = true; cancelRequested = false; restartRequired = false; log.Clear();
        cancelPath = Path.Combine(InternalSetup.Scratch, "cancel");
        bool success = false;
        try {
        Directory.CreateDirectory(InternalSetup.Scratch); if (File.Exists(cancelPath)) File.Delete(cancelPath);
        string logFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "neuralDoom", "SetupLogs");
        Directory.CreateDirectory(logFolder); logPath = Path.Combine(logFolder, "setup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
        ShowPage(3);
            int result = await Task.Run(delegate {
                if (!InternalSetup.Prepared) InternalSetup.Prepare();
                ProcessStartInfo start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"));
                start.UseShellExecute = false; start.CreateNoWindow = true; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
                start.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(InternalSetup.Bootstrap) + " -PackagePath " + Quote(InternalSetup.Payload) + " -Sha256 " + InternalSetup.Hash + " -Destination " + Quote(installPath) + " -GamePath " + Quote(gamePath) + " -NonInteractive" + (desktopShortcut ? "" : " -SkipShortcut");
                start.EnvironmentVariables["NEURALDOOM_SETUP_CANCEL_FILE"] = cancelPath;
                using (Process process = new Process { StartInfo = start }) {
                    process.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { Receive(e.Data); };
                    process.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { Receive(e.Data); };
                    process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine(); process.WaitForExit(); return process.ExitCode;
                }
            });
            success = result == 0;
        } catch (Exception error) { Receive(error.Message); }
        finally { running = false; try { if (logPath != null) File.WriteAllText(logPath, log.ToString()); } catch (IOException) {} ShowPage(success ? 4 : 5); }
    }
    void Receive(string line) {
        if (line == null) return;
        lock (log) { log.AppendLine(line); }
        BeginInvoke((Action)delegate {
            if (line.IndexOf("Windows requests a restart", StringComparison.OrdinalIgnoreCase) >= 0) restartRequired = true;
            if (line.StartsWith("@@SETUP|", StringComparison.Ordinal) && !cancelRequested) { status.Text = line.Substring(8); transfer.Text = "This can take a few minutes. You can leave setup running."; }
            if (details != null && !details.IsDisposed) { details.AppendText(line + Environment.NewLine); }
        });
    }
    static string FindBFG() {
        try {
            foreach (string key in new [] { @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 208200", @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 208200" }) {
                using (RegistryKey item = Registry.LocalMachine.OpenSubKey(key)) { string path = item == null ? null : item.GetValue("InstallLocation") as string; if (ValidGame(path)) return path; }
            }
            using (RegistryKey steam = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) {
                string path = steam == null ? null : steam.GetValue("SteamPath") as string;
                if (path != null) {
                    string candidate = Path.Combine(path, "steamapps", "common", "DOOM 3 BFG Edition"); if (ValidGame(candidate)) return candidate;
                    string vdf = Path.Combine(path, "steamapps", "libraryfolders.vdf");
                    if (File.Exists(vdf)) foreach (Match match in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\"")) {
                        candidate = Path.Combine(match.Groups[1].Value.Replace("\\\\", "\\"), "steamapps", "common", "DOOM 3 BFG Edition"); if (ValidGame(candidate)) return candidate;
                    }
                }
            }
        } catch (Exception) {}
        return "";
    }
    static bool ValidGame(string path) { return !String.IsNullOrEmpty(path) && File.Exists(Path.Combine(path, "base", "maps", "mars_city2.resources")); }
    internal void Preview(string directory) {
        Directory.CreateDirectory(directory); Show();
        for (int i = 0; i <= 5; i++) {
            ShowPage(i); Application.DoEvents();
            if (next.Visible && next.Left <= cancel.Right) throw new Exception("Wizard navigation overlaps.");
            using (Bitmap bitmap = new Bitmap(Width, Height)) { DrawToBitmap(bitmap, new Rectangle(Point.Empty, Size)); bitmap.Save(Path.Combine(directory, "setup-" + i + ".png")); }
        }
        Close();
    }
}
