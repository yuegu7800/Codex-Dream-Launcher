using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class CreateIconSet
{
    private static readonly int[] Sizes = { 16, 24, 32, 48, 64, 128, 256 };

    public static int Main(string[] args)
    {
        if (args == null || args.Length != 2) return 2;
        try {
            WriteIcon(args[0], false);
            WriteIcon(args[1], true);
            return 0;
        } catch (Exception ex) {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static void WriteIcon(string destinationPath, bool control)
    {
        List<byte[]> frames = new List<byte[]>();
        foreach (int size in Sizes) frames.Add(CreateFrame(size, control));
        string parent = Path.GetDirectoryName(destinationPath);
        if (!Directory.Exists(parent)) Directory.CreateDirectory(parent);
        using (FileStream stream = File.Create(destinationPath))
        using (BinaryWriter writer = new BinaryWriter(stream)) {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)frames.Count);
            int offset = 6 + frames.Count * 16;
            for (int index = 0; index < frames.Count; index++) {
                int size = Sizes[index];
                writer.Write((byte)(size == 256 ? 0 : size));
                writer.Write((byte)(size == 256 ? 0 : size));
                writer.Write((byte)0);
                writer.Write((byte)0);
                writer.Write((ushort)1);
                writer.Write((ushort)32);
                writer.Write(frames[index].Length);
                writer.Write(offset);
                offset += frames[index].Length;
            }
            foreach (byte[] frame in frames) writer.Write(frame);
        }
    }

    private static byte[] CreateFrame(int size, bool control)
    {
        using (Bitmap source = new Bitmap(256, 256, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(source))
        using (Bitmap target = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        using (Graphics scaled = Graphics.FromImage(target))
        using (MemoryStream output = new MemoryStream()) {
            g.Clear(control ? Color.FromArgb(242, 240, 248) : Color.FromArgb(239, 242, 248));
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.CompositingQuality = CompositingQuality.HighQuality;
            DrawMotif(g, control);
            if (control) DrawControls(g); else DrawLaunch(g);
            scaled.CompositingQuality = CompositingQuality.HighQuality;
            scaled.InterpolationMode = InterpolationMode.HighQualityBicubic;
            scaled.PixelOffsetMode = PixelOffsetMode.HighQuality;
            scaled.DrawImage(source, new Rectangle(0, 0, size, size));
            target.Save(output, ImageFormat.Png);
            return output.ToArray();
        }
    }

    private static void DrawMotif(Graphics g, bool control)
    {
        Color ink = Color.FromArgb(45, 49, 59);
        using (Pen ring = new Pen(ink, 10)) {
            ring.LineJoin = LineJoin.Round;
            for (int angle = 0; angle < 180; angle += 60) {
                GraphicsState state = g.Save();
                g.TranslateTransform(128, 103);
                g.RotateTransform(angle);
                g.DrawEllipse(ring, -47, -77, 94, 154);
                g.Restore(state);
            }
        }
        using (Brush accent = new SolidBrush(control ? Color.FromArgb(114, 91, 193) : Color.FromArgb(94, 175, 221))) {
            g.FillEllipse(accent, 119, 94, 18, 18);
        }
    }

    private static void DrawLaunch(Graphics g)
    {
        using (Pen accent = new Pen(Color.FromArgb(94, 175, 221), 11)) {
            accent.LineJoin = LineJoin.Round;
            g.DrawLines(accent, new[] { new Point(108, 139), new Point(128, 118), new Point(148, 139) });
        }
    }

    private static void DrawControls(Graphics g)
    {
        Color ink = Color.FromArgb(45, 49, 59);
        using (Pen pen = new Pen(ink, 6)) {
            int[] x = { 62, 91, 120 };
            int[] y = { 192, 178, 199 };
            for (int i = 0; i < x.Length; i++) {
                g.DrawLine(pen, x[i], 165, x[i], 217);
                g.DrawEllipse(pen, x[i] - 7, y[i] - 7, 14, 14);
            }
            g.DrawRectangle(pen, 152, 172, 48, 42);
            g.DrawLine(pen, 157, 207, 172, 191);
            g.DrawLine(pen, 172, 191, 184, 202);
            g.DrawLine(pen, 184, 202, 193, 190);
        }
        using (Brush purple = new SolidBrush(Color.FromArgb(114, 91, 193))) g.FillEllipse(purple, 113, 192, 14, 14);
        using (Brush mint = new SolidBrush(Color.FromArgb(94, 191, 170))) g.FillEllipse(mint, 84, 171, 14, 14);
    }
}
