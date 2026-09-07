// SPDX-License-Identifier: GPL-3.0-or-later
// Windows .NET Framework bootstrap. All application source is inside the payload.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;

class InternalSetup {
    static void Extract(string resource, string path) {
        using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource))
        using (FileStream target = new FileStream(path, FileMode.CreateNew)) { source.CopyTo(target); }
    }
    static int Main(string[] args) {
        string scratch = Path.Combine(Path.GetTempPath(), "neuralDoom-setup-" + Guid.NewGuid().ToString("N"));
        try {
            if (args.Length > 0 && (args.Length != 1 || args[0] != "--verify")) {
                Console.Error.WriteLine("Run setup with no arguments, or use --verify to check its embedded payload without installing.");
                return 2;
            }
            Directory.CreateDirectory(scratch);
            string zip = Path.Combine(scratch, "payload.zip");
            string script = Path.Combine(scratch, "Bootstrap-InternalSetup.ps1");
            Extract("Payload", zip);
            Extract("Bootstrap", script);
            string expected;
            using (StreamReader reader = new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream("Checksum"))) { expected = reader.ReadToEnd().Trim(); }
            string actual;
            using (SHA256 hash = SHA256.Create())
            using (FileStream file = File.OpenRead(zip)) { actual = BitConverter.ToString(hash.ComputeHash(file)).Replace("-", ""); }
            if (!String.Equals(expected, actual, StringComparison.OrdinalIgnoreCase)) { throw new Exception("Setup payload checksum failed."); }
            Console.WriteLine("neuralDoom setup: embedded payload verified.");
            if (args.Length == 1) { return 0; }
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            ProcessStartInfo start = new ProcessStartInfo(powershell);
            start.UseShellExecute = false;
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -PackagePath \"" + zip + "\" -Sha256 " + expected;
            using (Process process = Process.Start(start)) { process.WaitForExit(); if (process.ExitCode != 0) { throw new Exception("Setup could not finish. Read the error above, then run setup again."); } }
            Console.WriteLine("Setup complete. Use the neuralDoom Internal Test desktop shortcut.");
            Console.WriteLine("Press Enter to close."); Console.ReadLine();
            return 0;
        } catch (Exception error) {
            Console.Error.WriteLine(error.Message);
            if (args.Length == 0) { Console.WriteLine("Press Enter to close."); Console.ReadLine(); }
            return 1;
        } finally {
            // Only our randomly named temporary extraction directory is removed.
            string tempPrefix = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (Path.GetFullPath(scratch).StartsWith(tempPrefix, StringComparison.OrdinalIgnoreCase) && Directory.Exists(scratch)) { try { Directory.Delete(scratch, true); } catch {} }
        }
    }
}
