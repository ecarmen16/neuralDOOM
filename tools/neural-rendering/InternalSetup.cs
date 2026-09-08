// SPDX-License-Identifier: GPL-3.0-or-later
// Uses Windows' installed .NET Framework; no browser or extra UI runtime required.
using System;
using System.Collections.Generic;
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

// Button menus stay legible in dark mode and Windows accessibility previews.
class ChoiceButton : Button {
    internal readonly List<string> Items = new List<string>();
    readonly ContextMenuStrip menu = new ContextMenuStrip();
    int selected = -1;
    internal int SelectedIndex { get { return selected; } set { selected = value; Text = value >= 0 && value < Items.Count ? Items[value] + "   v" : "Select an installation...   v"; } }
    internal object SelectedItem { get { return selected >= 0 && selected < Items.Count ? Items[selected] : null; } set { SelectedIndex = Items.IndexOf(value as string); } }
    protected override void OnClick(EventArgs e) {
        base.OnClick(e);
        if (IsDisposed || Disposing || menu.Visible) return;
        menu.BackColor = BackColor; menu.ForeColor = ForeColor; menu.Font = Font;
        while (menu.Items.Count > 0) menu.Items[0].Dispose();
        for (int i = 0; i < Items.Count; i++) {
            int index = i; ToolStripMenuItem item = new ToolStripMenuItem(Items[i]) { Checked = index == selected };
            item.Click += delegate { SelectedIndex = index; }; menu.Items.Add(item);
        }
        menu.Show(this, new Point(0, Height));
    }
    protected override void Dispose(bool disposing) {
        // Closed runs before WinForms finishes dispatching the item click.
        // Keep the menu alive between selections and release it with its owner.
        if (disposing) menu.Dispose();
        base.Dispose(disposing);
    }
    protected override bool ProcessCmdKey(ref Message msg, Keys keyData) {
        if (Items.Count > 0 && (keyData == Keys.Left || keyData == Keys.Right)) { SelectedIndex = (selected + (keyData == Keys.Right ? 1 : Items.Count - 1)) % Items.Count; return true; }
        return base.ProcessCmdKey(ref msg, keyData);
    }
}

class SetupWindow : Form {
    readonly Color background = Color.FromArgb(19, 22, 27), panelColor = Color.FromArgb(28, 32, 39), ink = Color.FromArgb(240, 239, 236), muted = Color.FromArgb(158, 167, 181), accent = Color.FromArgb(232, 74, 58);
    Panel content, sidebar;
    Button next, back, cancel;
    TextBox destination, game, details;
    CheckBox shortcut;
    ChoiceButton renderer, operation, existing;
    TextBox dlssFile, nrFile;
    Label status, transfer;
    ProgressBar progress;
    int page;
    bool running, cancelRequested, showDetails, restartRequired;
    string installPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "neuralDoom", "Game"), gamePath = "", logPath, cancelPath;
    bool desktopShortcut = true;
    bool neuralAvailable;
    string profile = "Native", installMode = "New", existingPath = "", dlssPath = "", nrPath = "";
    readonly List<string> installations = new List<string>();
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
        next.Click += async delegate {
            if (page == 2 || page == 5) { await Install(); }
            else if (page == 4) { Close(); }
            else if (page == 7) { if (ReadManagement()) ShowPage(installMode == "Uninstall" ? 2 : 1); }
            else if (page == 1) { if (ValidateChoices()) ShowPage(6); }
            else if (page == 6) { if (ReadRenderer()) ShowPage(2); }
            else ShowPage(7);
        };
        back.Click += delegate {
            if (page == 1) { installPath = destination.Text.Trim(); gamePath = game.Text.Trim(); desktopShortcut = shortcut.Checked; }
            if (page == 6) { profile = neuralAvailable ? new [] { "NR", "DLAA", "Native" }[renderer.SelectedIndex] : "Native"; dlssPath = dlssFile.Text.Trim(); nrPath = nrFile.Text.Trim(); }
            ShowPage(page == 1 ? 7 : page == 6 ? 1 : page == 2 ? (installMode == "Uninstall" ? 7 : 6) : page == 5 ? 7 : 0);
        };
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
        using (Stream neural = Assembly.GetExecutingAssembly().GetManifestResourceStream("Neural")) {
            if (neural != null) using (StreamReader reader = new StreamReader(neural)) neuralAvailable = reader.ReadToEnd().Trim() == "1";
        }
        profile = neuralAvailable ? "NR" : "Native";
        gamePath = FindBFG(); FindInstallations();
        if (installations.Count > 0) { existingPath = installations[0]; installMode = "Upgrade"; }
        ShowPage(0);
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
    TextBox DllField(string value, int y, string name) {
        TextBox field = new TextBox { Text = value, Location = new Point(32, y), Size = new Size(472, 30), BackColor = panelColor, ForeColor = ink, BorderStyle = BorderStyle.FixedSingle };
        Button browse = MakeButton("Browse...", 516, y - 5, 110, false);
        browse.Click += delegate { using (OpenFileDialog picker = new OpenFileDialog()) {
            picker.Title = "Select " + name; picker.Filter = name + "|" + name; picker.CheckFileExists = true;
            if (picker.ShowDialog(this) == DialogResult.OK) field.Text = picker.FileName;
        } };
        content.Controls.Add(field); content.Controls.Add(browse); return field;
    }
    ChoiceButton Choice(string[] values, int selected, int y) {
        ChoiceButton field = new ChoiceButton { Location = new Point(32, y), Size = new Size(594, 38), FlatStyle = FlatStyle.Flat, BackColor = panelColor, ForeColor = ink, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true };
        field.FlatAppearance.BorderColor = muted;
        field.Items.AddRange(values); field.SelectedIndex = values.Length > 0 ? Math.Max(0, selected) : -1; content.Controls.Add(field); return field;
    }
    void DrawSidebar(object sender, PaintEventArgs e) {
        Graphics g = e.Graphics;
        using (Pen line = new Pen(Color.FromArgb(46, 32, 34), 2)) { for (int i = 0; i < 8; i++) g.DrawLine(line, -50, 330 + i * 32, 260, 160 + i * 32); }
        using (Font title = new Font("Segoe UI", 24, FontStyle.Bold)) g.DrawString("neural\nDOOM", title, Brushes.White, 23, 34);
        using (Brush red = new SolidBrush(accent)) g.FillRectangle(red, 26, 146, 40, 4);
        string[] steps = { "01   Welcome", "02   Install or manage", "03   Location", "04   Rendering", "05   Review", "06   Installation" };
        int active = page == 7 ? 1 : page == 1 ? 2 : page == 6 ? 3 : page == 2 ? 4 : page >= 3 ? 5 : 0;
        for (int i = 0; i < steps.Length; i++) using (Brush brush = new SolidBrush(i == active ? ink : muted)) {
            using (Font font = new Font("Segoe UI", 10, i == active ? FontStyle.Bold : FontStyle.Regular)) g.DrawString(steps[i], font, brush, 26, 208 + 42 * i);
        }
        using (Brush brush = new SolidBrush(muted))
        using (Font font = new Font("Segoe UI", 8)) g.DrawString("RTX + NEURAL RENDERING\nINTERNAL TEST BUILD", font, brush, 26, sidebar.Height - 66);
    }
    void ShowPage(int value) {
        page = value; while (content.Controls.Count > 0) content.Controls[0].Dispose(); sidebar.Invalidate();
        back.Visible = value == 1 || value == 2 || value == 5 || value == 6 || value == 7; back.Enabled = !running;
        next.Visible = value != 3; next.Text = value == 2 ? (installMode == "Uninstall" ? "Uninstall" : installMode == "Upgrade" ? "Upgrade" : "Install") : value == 4 ? "Finish" : value == 5 ? "Retry" : "Next";
        cancel.Visible = value != 4; cancel.Enabled = true; AcceptButton = next.Visible ? next : null;
        if (value == 0) {
            TextAt("A darker world.\nA new light.", 38, 116, 32, ink);
            TextAt("Welcome to neuralDoom", 181, 38, 19, ink);
            TextAt("Doom 3 atmosphere, with ray-traced lighting, material reflections, HDR and ultrawide support.", 233, 64, 12, muted);
            TextAt("Setup takes care of the downloads, supporting files and configuration. All you need is your installed copy of Doom 3 BFG Edition.", 320, 76, 11, muted);
            TextAt("Up to 2.1 GB to download  /  Allow 16 GB of free space", 431, 44, 10, ink);
        } else if (value == 7) {
            TextAt("Install. Upgrade. Make room.", 34, 56, 24, ink);
            TextAt(installations.Count == 0 ? "Choose a new installation or browse for an existing copy." : "Existing neuralDoom installations were found.", 104, 50, 11, muted);
            TextAt("ACTION", 164, 26, 9, muted);
            operation = Choice(new [] { "Upgrade / repair an existing installation", "Copy to a new folder, including saves and settings", "New separate installation", "Uninstall (keep saves and settings)" }, Array.IndexOf(new [] { "Upgrade", "Copy", "New", "Uninstall" }, installMode), 197);
            TextAt("EXISTING INSTALLATION", 258, 26, 9, muted);
            existing = Choice(installations.ToArray(), installations.IndexOf(existingPath), 292);
            Button browse = MakeButton("Find another...", 32, 340, 160, false); content.Controls.Add(browse);
            browse.Click += delegate { using (FolderBrowserDialog picker = new FolderBrowserDialog()) {
                picker.Description = "Select an existing neuralDoom installation"; picker.ShowNewFolderButton = false;
                if (picker.ShowDialog(this) == DialogResult.OK) {
                    if (!File.Exists(Path.Combine(picker.SelectedPath, "internal-package.json"))) { MessageBox.Show(this, "That folder does not contain a neuralDoom package."); return; }
                    if (!installations.Contains(picker.SelectedPath)) { installations.Add(picker.SelectedPath); existing.Items.Add(picker.SelectedPath); }
                    existing.SelectedItem = picker.SelectedPath;
                }
            } };
            TextAt("Upgrades back up replaced files and preserve saves and tuning.\nUninstall removes verified application files; personal files remain.", 416, 72, 11, muted);
        } else if (value == 6) {
            TextAt("Choose your rendering.", 34, 56, 25, ink);
            renderer = Choice(neuralAvailable ? new [] { "NR + DLAA - F6 comparison (experimental)", "DLAA / DLSS - native NVIDIA reconstruction", "Native RTX - no neural downloads" } : new [] { "Native RTX - this package has no neural engine" }, neuralAvailable ? Array.IndexOf(new [] { "NR", "DLAA", "Native" }, profile) : 0, 110);
            TextAt("DLAA renders at 100%. DLSS Quality, Balanced and Performance are optional in-game choices. NR keeps full-resolution DLAA input; F6 switches NR on/off. NR uses SDR output.", 162, 91, 11, muted);
            TextAt("Optional DLSS DLL  /  Leave blank for automatic download", 275, 28, 10, ink);
            dlssFile = DllField(dlssPath, 310, "nvngx_dlss.dll");
            TextAt("Optional NR DLL  /  Leave blank for automatic download", 354, 28, 10, ink);
            nrFile = DllField(nrPath, 388, "nvngx_dlssnr.dll");
            TextAt("Downloads: official Streamline and ReShade, plus pinned RHI community components. Component sources and terms are included in the installed notices.", 444, 65, 10, muted);
        } else if (value == 1) {
            TextAt("Make room for DOOM.", 34, 48, 25, ink);
            TextAt("Choose where to install. Your original game stays in place.", 96, 44, 11, muted);
            TextAt("Install neuralDoom to", 164, 30, 11, ink); destination = PathField(installPath, 200, false);
            if (installMode == "Upgrade") { destination.ReadOnly = true; }
            TextAt("Doom 3 BFG Edition game folder", 266, 30, 11, ink); game = PathField(gamePath, 304, true);
            TextAt(String.IsNullOrEmpty(gamePath) ? "Select the folder containing your owned BFG installation." : "BFG detected. You can select another copy if needed.", 346, 48, 10, muted);
            shortcut = new CheckBox { Text = "Create a desktop shortcut", Checked = desktopShortcut, ForeColor = ink, Location = new Point(32, 426), Size = new Size(350, 30) }; content.Controls.Add(shortcut);
        } else if (value == 2) {
            TextAt("Ready when you are.", 34, 54, 25, ink);
            TextAt("INSTALL LOCATION", 120, 28, 9, muted); TextAt(installPath, 150, 68, 11, ink);
            TextAt("GAME DATA SOURCE", 232, 28, 9, muted); TextAt(gamePath, 262, 68, 11, ink);
            TextAt(installMode == "Uninstall" ? "UNINSTALL - verified program files will be removed. Saves, settings, modified files and downloads will remain in this folder." : installMode.ToUpperInvariant() + " / " + profile + "\nSetup verifies downloads and prepares your chosen renderer. Existing saves and tuning are preserved.", 351, 80, 11, muted);
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
            TextAt(success ? (installMode == "Uninstall" ? "Application removed." : "Welcome back to Mars.") : cancelRequested ? "Setup paused." : "Let's get this sorted.", 34, 72, 25, ink);
            TextAt(success ? (installMode == "Uninstall" ? "Saves, settings and modified files remain in the installation folder." : restartRequired ? "Installation is complete. Restart Windows before playing." : "Installation complete. Your game is ready.") : cancelRequested ? "Setup stopped safely. You can retry using the verified files already downloaded." : "Setup couldn't finish. Your log has the details; you can retry after resolving the issue.", 138, 92, 12, muted);
            TextAt(success && installMode != "Uninstall" ? "Use the Start menu or your desktop shortcut to start.\n" + (profile == "NR" ? "F6 NR on/off (DLAA passthrough)\n" : "") + "F3 reflections · F4 bounce · F7 AO · F8 contact shadows\nF11 compares all four lighting effects together." : "Your original BFG installation has not been changed.", 259, 122, 11, ink);
            Button folder = MakeButton("Open install folder", 32, 402, 185, false); content.Controls.Add(folder);
            folder.Click += delegate { if (Directory.Exists(installPath)) Process.Start(new ProcessStartInfo(installPath) { UseShellExecute = true }); };
            Button logs = MakeButton("View setup log", 233, 402, 165, false); content.Controls.Add(logs);
            logs.Click += delegate { if (File.Exists(logPath)) Process.Start(new ProcessStartInfo("notepad.exe", Quote(logPath)) { UseShellExecute = false }); };
            if (success && installMode != "Uninstall") { Button guide = MakeButton("Test controls", 414, 402, 160, false); content.Controls.Add(guide); guide.Click += delegate { Process.Start(new ProcessStartInfo("notepad.exe", Quote(Path.Combine(installPath, "INTERNAL_TESTING.md"))) { UseShellExecute = false }); }; }
        }
    }
    bool ValidateChoices() {
        try {
            installPath = Path.GetFullPath(destination.Text.Trim()); gamePath = String.IsNullOrWhiteSpace(game.Text) ? "" : Path.GetFullPath(game.Text.Trim()); desktopShortcut = shortcut.Checked;
            if (!ValidGame(gamePath) && installMode == "Upgrade" && ValidGame(installPath)) gamePath = installPath;
            if (!ValidGame(gamePath)) throw new Exception("Select Doom 3 BFG Edition's installed folder, containing base. The original Doom 3 edition is not supported.");
            bool reuseInstalledData = installMode == "Upgrade" && String.Equals(installPath.TrimEnd('\\'), gamePath.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            if (!reuseInstalledData && (String.Equals(installPath.TrimEnd('\\'), gamePath.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase) || installPath.StartsWith(gamePath.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase) || gamePath.StartsWith(installPath.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))) throw new Exception("Choose a separate folder for neuralDoom, outside your owned game installation.");
            if (installMode == "Upgrade" && !String.Equals(installPath, existingPath, StringComparison.OrdinalIgnoreCase)) throw new Exception("Select a different existing installation on the previous page.");
            if (HasInstallContent(installPath) && (installMode != "Upgrade" || !File.Exists(Path.Combine(installPath, "internal-package.json")))) throw new Exception("Choose an empty folder for a new copy, or select Upgrade on the previous page.");
            string root = Path.GetPathRoot(installPath);
            if (new DriveInfo(root).AvailableFreeSpace < (installMode == "Upgrade" ? 4L : 16L) * 1024 * 1024 * 1024) throw new Exception("Allow 16 GB for a new installation or 4 GB for an upgrade and its backup.");
            return true;
        } catch (Exception error) { MessageBox.Show(this, error.Message, "Check your folders", MessageBoxButtons.OK, MessageBoxIcon.Information); return false; }
    }
    internal static bool HasInstallContent(string path) {
        if (!Directory.Exists(path)) return false;
        foreach (string entry in Directory.GetFileSystemEntries(path)) {
            string name = Path.GetFileName(entry);
            if ((name.Equals(".neuraldoom-cache", StringComparison.OrdinalIgnoreCase) || name.Equals("captures", StringComparison.OrdinalIgnoreCase)) && Directory.Exists(entry) && (File.GetAttributes(entry) & FileAttributes.ReparsePoint) == 0) continue;
            return true;
        }
        return false;
    }
    bool ReadManagement() {
        string selectedMode = new [] { "Upgrade", "Copy", "New", "Uninstall" }[operation.SelectedIndex];
        string selectedPath = selectedMode == "New" ? "" : existing.SelectedItem as string ?? "";
        if (selectedMode != "New" && !File.Exists(Path.Combine(selectedPath, "internal-package.json"))) { MessageBox.Show(this, "Select or browse to the existing installation first."); return false; }
        if (installMode == selectedMode && String.Equals(existingPath, selectedPath, StringComparison.OrdinalIgnoreCase)) return true;
        installMode = selectedMode; existingPath = selectedPath;
        if (installMode == "Upgrade" || installMode == "Uninstall") installPath = existingPath;
        else if (installMode == "Copy") { installPath = existingPath.TrimEnd('\\') + "-copy"; gamePath = existingPath; }
        else installPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "neuralDoom", "Game");
        return true;
    }
    bool ReadRenderer() {
        profile = neuralAvailable ? new [] { "NR", "DLAA", "Native" }[renderer.SelectedIndex] : "Native";
        dlssPath = dlssFile.Text.Trim(); nrPath = nrFile.Text.Trim();
        foreach (string path in new [] { profile != "Native" ? dlssPath : "", profile == "NR" ? nrPath : "" }) {
            if (path.Length > 0 && !File.Exists(path)) { MessageBox.Show(this, "Select an existing DLL, or clear the field for automatic download."); return false; }
        }
        return true;
    }
    void FindInstallations() {
        try {
            using (RegistryKey root = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
                if (root != null) foreach (string name in root.GetSubKeyNames()) if (name.StartsWith("neuralDoom-", StringComparison.OrdinalIgnoreCase)) {
                    using (RegistryKey item = root.OpenSubKey(name)) AddInstallation(item.GetValue("InstallLocation") as string);
                }
            }
            foreach (string folder in new [] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "neuralDoom", "Internal"), Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory) }) {
                if (Directory.Exists(folder)) foreach (string path in Directory.GetDirectories(folder)) AddInstallation(path);
            }
            AddInstallation(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "neuralDoom", "Game"));
        } catch (Exception) { }
    }
    void AddInstallation(string path) {
        if (!String.IsNullOrEmpty(path) && File.Exists(Path.Combine(path, "internal-package.json")) && !Directory.Exists(Path.Combine(path, ".git")) && !installations.Contains(path)) installations.Add(path);
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
                start.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(InternalSetup.Bootstrap) + " -PackagePath " + Quote(InternalSetup.Payload) + " -Sha256 " + InternalSetup.Hash + " -Destination " + Quote(installPath) + " -Mode " + installMode + " -Profile " + profile + " -NonInteractive" + (desktopShortcut ? "" : " -SkipShortcut");
                if (gamePath.Length > 0) start.Arguments += " -GamePath " + Quote(gamePath);
                if (existingPath.Length > 0) start.Arguments += " -ExistingPath " + Quote(existingPath);
                if (profile != "Native" && dlssPath.Length > 0) start.Arguments += " -DlssDllPath " + Quote(dlssPath);
                if (profile == "NR" && nrPath.Length > 0) start.Arguments += " -NRDllPath " + Quote(nrPath);
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
        for (int i = 0; i <= 7; i++) {
            ShowPage(i); Application.DoEvents();
            if (next.Visible && next.Left <= cancel.Right) throw new Exception("Wizard navigation overlaps.");
            using (Bitmap bitmap = new Bitmap(Width, Height)) { DrawToBitmap(bitmap, new Rectangle(Point.Empty, Size)); bitmap.Save(Path.Combine(directory, "setup-" + i + ".png")); }
        }
        Close();
    }
}
