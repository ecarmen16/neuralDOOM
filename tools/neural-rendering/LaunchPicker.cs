// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace NeuralDoom
{
    // Preserve native radio-button navigation and accessibility; only paint changes.
    sealed class RenderChoice : RadioButton
    {
        internal string Heading, Description, Badge;
        internal bool Compact;
        bool hovered;
        static readonly Color Accent = Color.FromArgb(240, 103, 65);
        internal RenderChoice(string heading, string description, string badge, bool compact)
        {
            Heading = heading; Description = description; Badge = badge; Compact = compact;
            Text = heading; AccessibleName = heading; AccessibleDescription = description;
            Appearance = Appearance.Button; FlatStyle = FlatStyle.Flat; AutoSize = false; Cursor = Cursors.Hand;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            CheckedChanged += delegate { Invalidate(); }; EnabledChanged += delegate { Invalidate(); };
        }
        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            float scale = e.Graphics.DpiX / 96.0f;
            int pad = (int)(16 * scale);
            Rectangle bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            Color fill = Checked ? Color.FromArgb(53, 34, 30) : hovered && Enabled ? Color.FromArgb(38, 41, 47) : Color.FromArgb(27, 30, 35);
            Color ink = Enabled ? Color.FromArgb(235, 235, 231) : Color.FromArgb(101, 106, 113);
            using (SolidBrush brush = new SolidBrush(fill)) e.Graphics.FillRectangle(brush, bounds);
            using (Pen pen = new Pen(Checked ? Accent : Color.FromArgb(62, 65, 71), Checked ? 2 * scale : scale)) e.Graphics.DrawRectangle(pen, bounds);
            if (Checked) using (SolidBrush brush = new SolidBrush(Accent)) e.Graphics.FillRectangle(brush, 0, 0, 3 * scale, Height);
            TextFormatFlags flags = TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis;
            using (Font title = new Font("Segoe UI", Compact ? 10 : 13, FontStyle.Bold))
            using (Font body = new Font("Segoe UI", Compact ? 9 : 9.5f))
            using (Font tag = new Font("Consolas", 8, FontStyle.Bold))
            {
                if (!Compact) TextRenderer.DrawText(e.Graphics, Enabled ? Badge : "NOT INSTALLED", tag, new Rectangle(pad, (int)(12 * scale), Width - pad * 2, (int)(16 * scale)), Checked ? Accent : Color.FromArgb(139, 145, 153), flags);
                int y = (int)((Compact ? 12 : 34) * scale);
                TextRenderer.DrawText(e.Graphics, Heading, title, new Rectangle(pad, y, Width - pad * 2, (int)(27 * scale)), ink, flags);
                TextRenderer.DrawText(e.Graphics, Description, body, new Rectangle(pad, y + (int)((Compact ? 23 : 30) * scale), Width - pad * 2, Height - y - (int)(30 * scale)), Enabled ? Color.FromArgb(166, 172, 181) : Color.FromArgb(101, 106, 113), flags | TextFormatFlags.WordBreak);
            }
            if (Focused) ControlPaint.DrawFocusRectangle(e.Graphics, new Rectangle(pad / 2, pad / 2, Width - pad, Height - pad), ink, fill);
        }
    }

    public sealed class LaunchPicker : Form
    {
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
        readonly RenderChoice[] profiles = new RenderChoice[3];
        readonly RenderChoice[] reconstruction = new RenderChoice[5];
        readonly Label details = new Label();
        readonly Label detailTitle = new Label();
        readonly Label status = new Label();
        readonly Label renderScale = new Label();
        readonly Panel scaleBar = new Panel();
        readonly ToolTip tips = new ToolTip();
        readonly string[] profileIds = { "Native", "DLAA", "NR" };
        int sdkMode, nrMode;
        bool updatingModes;
        static readonly Color Accent = Color.FromArgb(240, 103, 65);
        public event EventHandler SnapshotRequested;
        public string SelectedProfile
        {
            get { for (int i = 0; i < profiles.Length; i++) if (profiles[i] != null && profiles[i].Checked) return profileIds[i]; return "Native"; }
        }
        public int SelectedReconstruction { get { return SelectedProfile == "NR" ? nrMode : SelectedProfile == "DLAA" ? sdkMode : 0; } }
        public LaunchPicker(bool sdkAvailable, bool nrAvailable, string preferredProfile, int preferredMode)
            : this(sdkAvailable, nrAvailable, preferredProfile, preferredMode, 1) {}
        public LaunchPicker(bool sdkAvailable, bool nrAvailable, string preferredProfile, int preferredMode, int preferredNRMode)
        {
            sdkMode = Math.Max(0, Math.Min(4, preferredMode)); nrMode = Math.Max(1, Math.Min(4, preferredNRMode));
            Text = "neuralDoom | Render control"; ClientSize = new Size(900, 640);
            StartPosition = FormStartPosition.CenterScreen; FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; ShowInTaskbar = true;
            BackColor = Color.FromArgb(19, 21, 25); ForeColor = Color.FromArgb(235, 235, 231); Font = new Font("Segoe UI", 10);
            AutoScaleMode = AutoScaleMode.Dpi; AutoScaleDimensions = new SizeF(96, 96);
            AutoScroll = true; AutoScrollMinSize = ClientSize; DoubleBuffered = true;
            AddLabel("neuralDOOM", 30, 20, 540, 58, new Font("Bahnschrift", 35, FontStyle.Bold), ForeColor);
            AddLabel("MARS CITY  /  RENDER CONTROL", 33, 82, 540, 20, new Font("Consolas", 9), Color.FromArgb(156, 161, 170));
            AddLabel("01   RENDERING PROFILE", 32, 117, 700, 20, new Font("Consolas", 9, FontStyle.Bold), Accent);
            Panel profileGroup = new Panel { Location = new Point(32, 145), Size = new Size(840, 112), TabIndex = 0 };
            Controls.Add(profileGroup);
            profiles[0] = new RenderChoice("Native RTX", "Engine anti-aliasing.\nYour original reference.", "BASELINE", false);
            profiles[1] = new RenderChoice("DLAA / DLSS", "Neural anti-aliasing\nand reconstruction.", "NVIDIA", false);
            profiles[2] = new RenderChoice("Neural Rendering", "NR appearance processing\nwith DLAA or DLSS.", "EXPERIMENTAL", false);
            for (int i = 0; i < profiles.Length; i++)
            {
                RenderChoice choice = profiles[i]; choice.SetBounds(i * 285, 0, 270, 112); choice.TabIndex = i;
                profileGroup.Controls.Add(choice); choice.CheckedChanged += delegate { if (choice.Checked) UpdateModes(); };
            }
            profiles[1].Enabled = sdkAvailable; profiles[2].Enabled = sdkAvailable && nrAvailable;
            tips.SetToolTip(profiles[1], sdkAvailable ? "Use DLAA or select a DLSS reconstruction preset." : "Run setup to install the DLAA / DLSS components.");
            tips.SetToolTip(profiles[2], nrAvailable && sdkAvailable ? "Experimental appearance processing. F6 toggles NR during gameplay." : "Run setup to install the local Neural Rendering components.");
            AddLabel("02   RECONSTRUCTION", 32, 280, 700, 20, new Font("Consolas", 9, FontStyle.Bold), Accent);
            Panel modeGroup = new Panel { Location = new Point(32, 309), Size = new Size(840, 72), TabIndex = 1 };
            Controls.Add(modeGroup);
            string[] names = { "Native TAA", "DLAA", "Quality", "Balanced", "Performance" };
            string[] scales = { "100% / native", "100% / native", "~67% per axis", "~58% per axis", "~50% per axis" };
            for (int i = 0; i < reconstruction.Length; i++)
            {
                int mode = i; RenderChoice choice = new RenderChoice(names[i], scales[i], "", true); reconstruction[i] = choice;
                choice.SetBounds(i * 170, 0, 160, 72); choice.TabIndex = i; modeGroup.Controls.Add(choice);
                choice.CheckedChanged += delegate {
                    if (updatingModes || !choice.Checked) return;
                    if (SelectedProfile == "NR") nrMode = mode; else if (SelectedProfile == "DLAA") sdkMode = mode;
                    UpdateDetails();
                };
            }
            detailTitle.SetBounds(32, 411, 590, 24); detailTitle.Font = new Font("Segoe UI", 12, FontStyle.Bold); Controls.Add(detailTitle);
            details.SetBounds(32, 443, 590, 65); details.ForeColor = Color.FromArgb(174, 180, 189); Controls.Add(details);
            renderScale.SetBounds(671, 401, 200, 45); renderScale.Font = new Font("Bahnschrift", 26, FontStyle.Bold); renderScale.ForeColor = Accent; Controls.Add(renderScale);
            AddLabel("INTERNAL RENDER SCALE", 675, 447, 202, 18, new Font("Consolas", 8), Color.FromArgb(156, 161, 170));
            Panel barTrack = new Panel { Location = new Point(675, 477), Size = new Size(193, 4), BackColor = Color.FromArgb(54, 58, 64) };
            scaleBar.BackColor = Accent; scaleBar.Height = 4; barTrack.Controls.Add(scaleBar); Controls.Add(barTrack);
            status.SetBounds(32, 520, 840, 30); status.Font = new Font("Segoe UI", 9); status.ForeColor = Color.FromArgb(142, 149, 160); Controls.Add(status);
            Button reset = MakeButton("Restore defaults...", 32, 578, 165, false); reset.TabIndex = 2;
            reset.AccessibleDescription = "Reset game and ReShade settings. Saved games and progress are preserved; current settings are backed up.";
            reset.Click += delegate {
                if (MessageBox.Show(this, "Restore the shipped game, video, controls, audio and ReShade / NR settings?\n\nSaved games and progress are preserved. Your current settings will be backed up first. Close the game before resetting.\n\nYou can choose a rendering profile again afterward.", "Restore defaults", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) == DialogResult.OK)
                    DialogResult = DialogResult.Retry;
            };
            Button snapshot = MakeButton("Save snapshot...", 211, 578, 170, false); snapshot.TabIndex = 3;
            snapshot.AccessibleDescription = "Save the last written game and ReShade / NR settings to a personal ZIP. Close Doom 3 first. Settings are not changed.";
            tips.SetToolTip(snapshot, "Save settings after exiting the game. Snapshot ZIPs stay local; they are not shipped defaults.");
            snapshot.Click += delegate { if (SnapshotRequested != null) SnapshotRequested(this, EventArgs.Empty); };
            Button cancel = MakeButton("Cancel", 597, 578, 105, false); cancel.TabIndex = 4; cancel.DialogResult = DialogResult.Cancel;
            Button play = MakeButton("PLAY DOOM 3", 716, 578, 156, true); play.TabIndex = 5; play.DialogResult = DialogResult.OK;
            AcceptButton = play; CancelButton = cancel;
            int preferred = Array.IndexOf(profileIds, preferredProfile);
            if (preferred < 0 || !profiles[preferred].Enabled) preferred = profiles[2].Enabled ? 2 : profiles[1].Enabled ? 1 : 0;
            profiles[preferred].Checked = true;
        }
        void AddLabel(string text, int x, int y, int width, int height, Font font, Color color)
        {
            Controls.Add(new Label { Text = text, Location = new Point(x, y), Size = new Size(width, height), Font = font, ForeColor = color, BackColor = Color.Transparent });
        }
        Button MakeButton(string text, int x, int y, int width, bool primary)
        {
            Button button = new Button { Text = text, FlatStyle = FlatStyle.Flat, BackColor = primary ? Accent : BackColor, ForeColor = primary ? Color.FromArgb(24, 19, 17) : ForeColor, Font = new Font("Segoe UI", 10, primary ? FontStyle.Bold : FontStyle.Regular), Cursor = Cursors.Hand };
            button.SetBounds(x, y, width, 40); button.FlatAppearance.BorderColor = primary ? Accent : Color.FromArgb(66, 71, 79); Controls.Add(button); return button;
        }
        protected override void OnLoad(EventArgs e)
        {
            base.OnLoad(e);
            // Scroll rather than hide controls on small desktops / large DPI scales.
            Rectangle work = Screen.FromPoint(Cursor.Position).WorkingArea;
            Size = new Size(Math.Min(Width, work.Width), Math.Min(Height, work.Height));
            Location = new Point(work.Left + (work.Width - Width) / 2, work.Top + (work.Height - Height) / 2);
        }
        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            BeginInvoke(new MethodInvoker(delegate {
                if (IsDisposed || !Visible) return;
                WindowState = FormWindowState.Normal;
                // A minimized host can supply a minimized native first-show state.
                ShowWindow(Handle, 9); // SW_RESTORE, once for this user-initiated dialog.
                BringToFront(); Activate();
            }));
        }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            base.OnPaintBackground(e); float scale = e.Graphics.DpiX / 96.0f;
            using (LinearGradientBrush gradient = new LinearGradientBrush(new Rectangle(0, 0, Width, Math.Max(1, (int)(105 * scale))), BackColor, Color.FromArgb(47, 28, 26), 0.0f))
                e.Graphics.FillRectangle(gradient, 0, 0, Width, 105 * scale);
            using (Pen line = new Pen(Color.FromArgb(76, 51, 44), scale))
                for (int i = 0; i < 8; i++) e.Graphics.DrawLine(line, (650 + i * 36) * scale, 0, (575 + i * 36) * scale, 105 * scale);
            using (Pen line = new Pen(Color.FromArgb(52, 56, 64), scale))
                e.Graphics.DrawLine(line, 32 * scale, 558 * scale + AutoScrollPosition.Y, 872 * scale, 558 * scale + AutoScrollPosition.Y);
        }
        void UpdateModes()
        {
            if (reconstruction[0] == null) return;
            updatingModes = true;
            for (int i = 0; i < reconstruction.Length; i++)
            {
                reconstruction[i].Enabled = SelectedProfile == "DLAA" || (SelectedProfile == "NR" && i > 0) || (SelectedProfile == "Native" && i == 0);
                reconstruction[i].Checked = i == SelectedReconstruction;
            }
            updatingModes = false; UpdateDetails();
        }
        void UpdateDetails()
        {
            int mode = SelectedReconstruction;
            string[] titles = { "Full-resolution engine anti-aliasing", "Native resolution. Neural anti-aliasing.", "Detail first", "A balance of detail and speed", "Lower rendering cost" };
            string[] descriptions = {
                "Engine TAA at your display resolution. A useful baseline for comparing rendering modes.",
                "DLAA works at full resolution to stabilize edges and retain fine detail.",
                "DLSS reconstructs from about 44% of native pixels. The highest input resolution of the upscale presets.",
                "DLSS reconstructs from about 34% of native pixels, trading some fine detail for a lower rendering cost.",
                "DLSS reconstructs from about 25% of native pixels. Thin details and motion can look softer; FPS gains depend on the scene."
            };
            detailTitle.Text = titles[mode];
            details.Text = descriptions[mode] + (SelectedProfile == "NR" ? " Experimental NR adds appearance processing and rendering cost." : " Your RTX lighting settings are preserved.");
            status.Text = SelectedProfile == "NR" ? "SDR output  /  Native-resolution HUD  /  F1 reconstruction  /  F6 NR on or off"
                : SelectedProfile == "DLAA" ? "Native HDR available in System Options  /  Native-resolution HUD  /  F1 reconstruction"
                : "Native HDR available in System Options  /  Neural components are not required";
            float[] fractions = { 1, 1, 0.67f, 0.58f, 0.5f };
            renderScale.Text = (mode >= 2 ? "~" : "") + Math.Round(fractions[mode] * 100) + "%";
            scaleBar.Width = (int)(scaleBar.Parent.ClientSize.Width * fractions[mode]);
        }
        protected override void Dispose(bool disposing) { if (disposing) tips.Dispose(); base.Dispose(disposing); }
    }
}
