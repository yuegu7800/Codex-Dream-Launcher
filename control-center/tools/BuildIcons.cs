using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class BuildIcons
{
    private static readonly int[] Sizes = { 16, 24, 32, 48, 64, 128, 256 };

    public static int Main(string[] args)
    {
        if (args == null || args.Length != 2) return 2;
        try {
            WriteIcon(args[0], args[1]);
            return 0;
        } catch (Exception ex) {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static void WriteIcon(string sourcePath, string destinationPath)
    {
        List<byte[]> frames = new List<byte[]>();
        using (Image source = Image.FromFile(sourcePath)) {
            foreach (int size in Sizes) frames.Add(CreatePngFrame(source, size));
        }

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

    private static byte[] CreatePngFrame(Image source, int size)
    {
        using (Bitmap bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        using (Graphics graphics = Graphics.FromImage(bitmap))
        using (MemoryStream output = new MemoryStream()) {
            graphics.Clear(Color.Transparent);
            graphics.CompositingQuality = CompositingQuality.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.SmoothingMode = SmoothingMode.HighQuality;
            graphics.DrawImage(source, new Rectangle(0, 0, size, size));
            bitmap.Save(output, ImageFormat.Png);
            return output.ToArray();
        }
    }
}
