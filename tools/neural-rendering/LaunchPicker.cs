// SPDX-License-Identifier: GPL-3.0-or-later
using System;
using System.Drawing;
using System.Windows.Forms;

namespace NeuralDoom
{
    public sealed class LaunchPicker : Form
    {
        readonly ComboBox profiles = new ComboBox();
        readonly ComboBox reconstruction = new ComboBox();
        readonly Label details = new Label();
        readonly Label fixedMode = new Label();
        int sdkMode;
        int nrMode;
        bool updatingModes;

        public string SelectedProfile
        {
            get { return profiles.SelectedItem.ToString() == "NR + DLAA / DLSS" ? "NR" : profiles.SelectedItem.ToString() == "DLAA / DLSS" ? "DLAA" : "Native"; }
        }
        public int SelectedReconstruction { get { return SelectedProfile == "NR" ? nrMode : SelectedProfile == "DLAA" ? sdkMode : 0; } }

        public LaunchPicker(bool sdkAvailable, bool nrAvailable, string preferredProfile, int preferredMode)
            : this(sdkAvailable, nrAvailable, preferredProfile, preferredMode, 1) {}

        public LaunchPicker(bool sdkAvailable, bool nrAvailable, string preferredProfile, int preferredMode, int preferredNRMode)
        {
            sdkMode = Math.Max(0, Math.Min(4, preferredMode));
            nrMode = Math.Max(1, Math.Min(4, preferredNRMode));
            Text = "neuralDoom";
            ClientSize = new Size(640, 530);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            BackColor = Color.FromArgb(24, 26, 30);
            ForeColor = Color.Gainsboro;
            Font = new Font("Segoe UI", 10);
            AutoScaleMode = AutoScaleMode.Dpi;
            AutoScaleDimensions = new SizeF(96, 96);
            Controls.Add(new Label { Text = "neuralDoom", Font = new Font("Segoe UI", 24, FontStyle.Bold), AutoSize = true, Location = new Point(28, 20) });
            Controls.Add(new Label { Text = "Choose how to render. Play opens the Doom 3 menu.", AutoSize = true, Location = new Point(30, 76) });
            Controls.Add(new Label { Text = "Rendering profile", AutoSize = true, Location = new Point(30, 118) });
            profiles.SetBounds(30, 144, 280, 30);
            profiles.DropDownStyle = ComboBoxStyle.DropDownList;
            profiles.AccessibleName = "Rendering profile";
            if (nrAvailable && sdkAvailable) profiles.Items.Add("NR + DLAA / DLSS");
            if (sdkAvailable) profiles.Items.Add("DLAA / DLSS");
            profiles.Items.Add("Native RTX");
            Controls.Add(profiles);

            Controls.Add(new Label { Text = "Reconstruction", AutoSize = true, Location = new Point(330, 118) });
            reconstruction.SetBounds(330, 144, 280, 30);
            reconstruction.DropDownStyle = ComboBoxStyle.DropDownList;
            reconstruction.AccessibleName = "DLAA / DLSS quality";
            Controls.Add(reconstruction);
            fixedMode.SetBounds(330, 148, 280, 30);
            Controls.Add(fixedMode);

            details.SetBounds(30, 202, 580, 252);
            Controls.Add(details);
            Button play = new Button { Text = "Play Doom 3", DialogResult = DialogResult.OK, BackColor = Color.FromArgb(151, 40, 40), ForeColor = Color.White, FlatStyle = FlatStyle.Flat };
            play.SetBounds(438, 466, 172, 38);
            Controls.Add(play);
            Button cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, FlatStyle = FlatStyle.Flat };
            cancel.SetBounds(316, 466, 108, 38);
            Controls.Add(cancel);
            AcceptButton = play;
            CancelButton = cancel;

            profiles.SelectedIndexChanged += delegate { UpdateModes(); };
            reconstruction.SelectedIndexChanged += delegate {
                if (updatingModes || reconstruction.SelectedIndex < 0) return;
                if (SelectedProfile == "NR") nrMode = reconstruction.SelectedIndex + 1;
                else if (SelectedProfile == "DLAA") sdkMode = reconstruction.SelectedIndex;
                UpdateDetails();
            };
            string preferred = preferredProfile == "NR" ? "NR + DLAA / DLSS" : preferredProfile == "DLAA" ? "DLAA / DLSS" : preferredProfile == "Native" ? "Native RTX" : "";
            profiles.SelectedIndex = profiles.Items.Contains(preferred) ? profiles.Items.IndexOf(preferred) : 0;
        }

        void UpdateModes()
        {
            if (profiles.SelectedIndex < 0) return;
            updatingModes = true;
            reconstruction.Items.Clear();
            if (SelectedProfile == "DLAA") reconstruction.Items.Add("Native TAA (100%)");
            if (SelectedProfile != "Native")
            {
                reconstruction.Items.AddRange(new object[] { "DLAA (100%)", "DLSS Quality (~67%)", "DLSS Balanced (~58%)", "DLSS Performance (~50%)" });
                reconstruction.SelectedIndex = SelectedProfile == "NR" ? nrMode - 1 : sdkMode;
            }
            reconstruction.Enabled = SelectedProfile != "Native";
            reconstruction.Visible = reconstruction.Enabled;
            fixedMode.Visible = !reconstruction.Enabled;
            fixedMode.Text = "Native TAA (100%)";
            updatingModes = false;
            UpdateDetails();
        }

        void UpdateDetails()
        {
            string text;
            if (SelectedProfile != "Native")
            {
                string[] descriptions = {
                    "Native TAA: full-resolution engine anti-aliasing, with the SDK profile still loaded. Useful for an in-game comparison with DLAA.",
                    "DLAA: full-resolution NVIDIA anti-aliasing. Prioritizes edge stability and detail; does not reduce rendering resolution to increase FPS.",
                    "DLSS Quality: about 67% resolution per axis (~44% of native pixels). The most detail-preserving upscale preset; may improve FPS when GPU limited.",
                    "DLSS Balanced: about 58% resolution per axis (~34% of native pixels). Trades more fine detail and motion stability for lower rendering cost.",
                    "DLSS Performance: about 50% resolution per axis (~25% of native pixels). Greatest rendering reduction; thin details and motion can look softer or less stable."
                };
                text = descriptions[SelectedReconstruction];
                text += SelectedProfile == "NR"
                    ? "\n\nExperimental NR appearance processing can change lighting and detail. NR + DLSS needs branch testing. F6 toggles NR, keeping this reconstruction; NR may still add substantial cost. Output/HUD stay native. Uses embedded compatibility components; native HDR is unavailable."
                    : "\n\nOutput resolution and HUD stay native. Native HDR is available on a compatible display; enable it in System Options. NR is not loaded, so F6 has no effect. Quality can be changed in-game.";
            }
            else
                text = "Native RTX: full-resolution engine TAA with our ray-traced lighting. No NVIDIA reconstruction or NR runtime is loaded. Useful as a baseline on supported DX12 ray-tracing hardware.\n\nNative HDR is available on a compatible display. F6 has no effect. Run setup in Upgrade / repair mode to add missing neural components.";
            details.Text = text + "\n\nAll profiles keep your RTX lighting settings. FPS gains depend on the scene; NVIDIA Reflex is not integrated. Your selection is remembered after a normal game exit.";
        }
    }
}
