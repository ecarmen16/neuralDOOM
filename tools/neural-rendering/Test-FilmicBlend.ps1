[CmdletBinding()]
param([Parameter(Mandatory)][string]$ScreenshotDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('FilmicBlendCheck' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.IO;
public static class FilmicBlendCheck {
    public static string Check(string path) {
        using (var off = new Bitmap(Path.Combine(path, "filmic_off.png")))
        using (var zero = new Bitmap(Path.Combine(path, "filmic_zero.png")))
        using (var half = new Bitmap(Path.Combine(path, "filmic_half.png")))
        using (var full = new Bitmap(Path.Combine(path, "filmic_full.png"))) {
            if (off.Size != zero.Size || off.Size != half.Size || off.Size != full.Size) throw new Exception("Filmic capture sizes differ.");
            double bypassError = 0, blendError = 0, effect = 0;
            for (int y = 0; y < off.Height; y++) for (int x = 0; x < off.Width; x++) {
                Color a = off.GetPixel(x,y), b = zero.GetPixel(x,y), c = half.GetPixel(x,y), d = full.GetPixel(x,y);
                bypassError += Math.Abs(a.R-b.R) + Math.Abs(a.G-b.G) + Math.Abs(a.B-b.B);
                blendError += Math.Abs(c.R-(b.R+d.R)*0.5) + Math.Abs(c.G-(b.G+d.G)*0.5) + Math.Abs(c.B-(b.B+d.B)*0.5);
                effect += Math.Abs(d.R-b.R) + Math.Abs(d.G-b.G) + Math.Abs(d.B-b.B);
            }
            double samples = off.Width * off.Height * 3.0;
            bypassError /= samples; blendError /= samples; effect /= samples;
            string result = String.Format(System.Globalization.CultureInfo.InvariantCulture, "bypassError={0:F4}, halfBlendError={1:F4}, fullEffect={2:F4} (8-bit channel means)", bypassError, blendError, effect);
            if (bypassError > 0.05 || blendError > 0.75 || effect < 0.1) throw new Exception("Filmic blend regression: " + result);
            return "PASS: Filmic zero matches disabled; 50% blends both endpoints; " + result;
        }
    }
}
'@
}
[FilmicBlendCheck]::Check((Resolve-Path -LiteralPath $ScreenshotDirectory).Path)
