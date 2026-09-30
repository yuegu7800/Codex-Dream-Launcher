using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using IOPath = System.IO.Path;

namespace CodexDreamControlCenter
{
    [DataContract]
    public sealed class ControlConfig
    {
        [DataMember] public bool workspaceEnabled;
        [DataMember] public string workspaceImage;
        [DataMember] public double workspaceOpacity;
        [DataMember] public string targetProcess;
        [DataMember] public bool syncStartupWallpaper;

        public static ControlConfig Defaults()
        {
            return new ControlConfig {
                workspaceEnabled = false,
                workspaceImage = "assets\\violet-evergarden.jpg",
                workspaceOpacity = 0.035,
                targetProcess = "ChatGPT",
                syncStartupWallpaper = true
            };
        }
    }

    internal static class NativeMethods
    {
        internal const int GwlExStyle = -20;
        internal const long WsExTransparent = 0x00000020L;
        internal const long WsExToolWindow = 0x00000080L;
        internal const long WsExNoActivate = 0x08000000L;

        [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] internal static extern bool IsHungAppWindow(IntPtr hWnd);
        [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr hWnd, out RectNative rect);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)] internal static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)] internal static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int index, IntPtr value);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RectNative { internal int Left, Top, Right, Bottom; }

        internal static IntPtr GetWindowLongPtr(IntPtr hWnd, int index)
        {
            return GetWindowLongPtr64(hWnd, index);
        }

        internal static void SetWindowLongPtr(IntPtr hWnd, int index, IntPtr value)
        {
            SetWindowLongPtr64(hWnd, index, value);
        }
    }

    internal static class OverlaySignal
    {
        internal const string StopEventName = "Local\\CodexDreamControlCenter.StopOverlay";

        internal static void Stop()
        {
            try {
                using (EventWaitHandle signal = EventWaitHandle.OpenExisting(StopEventName)) signal.Set();
            } catch (WaitHandleCannotBeOpenedException) {
            }
        }
    }

    public sealed class OverlayWindow : Window
    {
        private readonly ControlConfig config;
        private readonly string baseDirectory;
        private readonly DispatcherTimer timer;
        private readonly EventWaitHandle stopSignal;
        private readonly RegisteredWaitHandle stopRegistration;
        private DateTime? noTargetSince;
        private Border wallpaperLayer;
        private DateTime configLastWriteUtc;

        public OverlayWindow(ControlConfig config, string baseDirectory)
        {
            this.config = config;
            this.baseDirectory = baseDirectory;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = true;
            IsHitTestVisible = false;
            Content = BuildImage();
            SourceInitialized += OnSourceInitialized;
            Closed += OnClosed;

            timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
            timer.Tick += Poll;
            stopSignal = new EventWaitHandle(false, EventResetMode.AutoReset, OverlaySignal.StopEventName);
            stopRegistration = ThreadPool.RegisterWaitForSingleObject(stopSignal, delegate { Dispatcher.BeginInvoke(new Action(Close)); }, null, -1, true);
        }

        private UIElement BuildImage()
        {
            Grid root = new Grid { IsHitTestVisible = false };
            wallpaperLayer = new Border {
                Margin = new Thickness(220, 72, 0, 0),
                IsHitTestVisible = false,
                OpacityMask = new RadialGradientBrush {
                    Center = new Point(0.88, 0.83),
                    GradientOrigin = new Point(0.88, 0.83),
                    RadiusX = 0.82,
                    RadiusY = 0.92,
                    GradientStops = new GradientStopCollection {
                        new GradientStop(Colors.White, 0),
                        new GradientStop(Color.FromArgb(185, 255, 255, 255), 0.45),
                        new GradientStop(Color.FromArgb(55, 255, 255, 255), 0.78),
                        new GradientStop(Colors.Transparent, 1)
                    }
                }
            };
            root.Children.Add(wallpaperLayer);
            ApplyAppearance();
            return root;
        }

        private void OnSourceInitialized(object sender, EventArgs e)
        {
            IntPtr handle = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            long style = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GwlExStyle).ToInt64();
            style |= NativeMethods.WsExTransparent | NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate;
            NativeMethods.SetWindowLongPtr(handle, NativeMethods.GwlExStyle, new IntPtr(style));
        }

        protected override void OnContentRendered(EventArgs e)
        {
            base.OnContentRendered(e);
            timer.Start();
            Poll(this, EventArgs.Empty);
        }

        private void Poll(object sender, EventArgs e)
        {
            ReloadAppearanceIfChanged();
            IntPtr target = FindForegroundTarget();
            if (target == IntPtr.Zero) {
                Hide();
                if (!AnyTargetProcess()) {
                    if (!noTargetSince.HasValue) noTargetSince = DateTime.UtcNow;
                    if ((DateTime.UtcNow - noTargetSince.Value).TotalMilliseconds > 1800) Close();
                } else {
                    noTargetSince = null;
                }
                return;
            }

            noTargetSince = null;
            NativeMethods.RectNative rect;
            if (!NativeMethods.GetWindowRect(target, out rect)) return;
            Left = rect.Left;
            Top = rect.Top;
            Width = Math.Max(1, rect.Right - rect.Left);
            Height = Math.Max(1, rect.Bottom - rect.Top);
            if (!IsVisible) Show();
        }

        private IntPtr FindForegroundTarget()
        {
            IntPtr foreground = NativeMethods.GetForegroundWindow();
            if (foreground == IntPtr.Zero || !NativeMethods.IsWindowVisible(foreground) || NativeMethods.IsHungAppWindow(foreground)) return IntPtr.Zero;
            uint processId;
            NativeMethods.GetWindowThreadProcessId(foreground, out processId);
            string processName = string.IsNullOrWhiteSpace(config.targetProcess) ? "ChatGPT" : config.targetProcess;
            try {
                Process process = Process.GetProcessById((int)processId);
                return string.Equals(process.ProcessName, processName, StringComparison.OrdinalIgnoreCase) ? foreground : IntPtr.Zero;
            } catch {
                return IntPtr.Zero;
            }
        }

        private bool AnyTargetProcess()
        {
            string processName = string.IsNullOrWhiteSpace(config.targetProcess) ? "ChatGPT" : config.targetProcess;
            return Process.GetProcessesByName(processName).Length > 0;
        }

        private void ReloadAppearanceIfChanged()
        {
            try {
                string path = IOPath.Combine(baseDirectory, "launcher.json");
                DateTime changed = File.GetLastWriteTimeUtc(path);
                if (changed <= configLastWriteUtc) return;
                ControlConfig updated = Program.LoadConfig(path);
                config.workspaceImage = updated.workspaceImage;
                config.workspaceOpacity = updated.workspaceOpacity;
                configLastWriteUtc = changed;
                ApplyAppearance();
            } catch {
            }
        }

        private void ApplyAppearance()
        {
            if (wallpaperLayer == null) return;
            wallpaperLayer.Opacity = Math.Max(0.01, Math.Min(0.10, config.workspaceOpacity));
            string path = ResolvePath(config.workspaceImage);
            if (!File.Exists(path)) {
                wallpaperLayer.Background = Brushes.Transparent;
                return;
            }
            try {
                wallpaperLayer.Background = new ImageBrush(new BitmapImage(new Uri(path, UriKind.Absolute))) {
                    Stretch = Stretch.UniformToFill,
                    AlignmentX = AlignmentX.Right,
                    AlignmentY = AlignmentY.Bottom
                };
            } catch {
                wallpaperLayer.Background = Brushes.Transparent;
            }
        }

        private string ResolvePath(string value)
        {
            return IOPath.IsPathRooted(value) ? value : IOPath.GetFullPath(IOPath.Combine(baseDirectory, value));
        }

        private void OnClosed(object sender, EventArgs e)
        {
            timer.Stop();
            stopRegistration.Unregister(null);
            stopSignal.Dispose();
        }
    }

    public sealed class ControlCenterWindow : Window
    {
        private readonly string baseDirectory;
        private readonly string configPath;
        private ControlConfig config;
        private Image preview;
        private TextBlock imagePathText;
        private Slider opacitySlider;
        private CheckBox syncStartupCheck;
        private TextBlock status;

        public ControlCenterWindow(string baseDirectory)
        {
            this.baseDirectory = baseDirectory;
            configPath = IOPath.Combine(baseDirectory, "launcher.json");
            config = Program.LoadConfig(configPath);
            Title = "Codex Dream Control Center";
            Width = 880;
            Height = 670;
            MinWidth = 760;
            MinHeight = 610;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            Background = new SolidColorBrush(Color.FromRgb(20, 22, 30));
            Content = BuildLayout();
            RefreshPreview();
        }

        private UIElement BuildLayout()
        {
            Grid root = new Grid { Margin = new Thickness(26) };
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            StackPanel heading = new StackPanel();
            heading.Children.Add(Text("CODEX DREAM", 28, Brushes.White, FontWeights.SemiBold));
            heading.Children.Add(Text("壁纸与工作区视觉覆盖层", 15, new SolidColorBrush(Color.FromRgb(184, 193, 211)), FontWeights.Normal));
            Grid.SetRow(heading, 0);
            root.Children.Add(heading);

            Grid body = new Grid { Margin = new Thickness(0, 24, 0, 20) };
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.15, GridUnitType.Star) });
            body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.85, GridUnitType.Star) });
            Grid.SetRow(body, 1);
            root.Children.Add(body);

            Border previewFrame = PanelBorder();
            preview = new Image { Stretch = Stretch.UniformToFill };
            previewFrame.Child = preview;
            Grid.SetColumn(previewFrame, 0);
            body.Children.Add(previewFrame);

            StackPanel controls = new StackPanel { Margin = new Thickness(22, 0, 0, 0) };
            controls.Children.Add(Text("壁纸", 18, Brushes.White, FontWeights.SemiBold));
            imagePathText = Text("", 12, new SolidColorBrush(Color.FromRgb(174, 183, 200)), FontWeights.Normal);
            imagePathText.TextWrapping = TextWrapping.Wrap;
            imagePathText.Margin = new Thickness(0, 7, 0, 12);
            controls.Children.Add(imagePathText);
            Button choose = ButtonOf("选择本地图片");
            choose.Click += ChooseImage;
            controls.Children.Add(choose);

            controls.Children.Add(Separator(22));
            controls.Children.Add(Text("实验性工作区视觉覆盖层", 18, Brushes.White, FontWeights.SemiBold));
            TextBlock note = Text("外部低透明度、鼠标穿透覆盖层。不会注入或修改 Codex；仅在 Codex 位于前台时可见。", 12, new SolidColorBrush(Color.FromRgb(190, 197, 210)), FontWeights.Normal);
            note.TextWrapping = TextWrapping.Wrap;
            note.Margin = new Thickness(0, 7, 0, 12);
            controls.Children.Add(note);
            controls.Children.Add(Text("透明度", 13, Brushes.White, FontWeights.Normal));
            opacitySlider = new Slider { Minimum = 1, Maximum = 10, Value = Math.Round(config.workspaceOpacity * 100), TickFrequency = 1, IsSnapToTickEnabled = true, Margin = new Thickness(0, 5, 0, 13) };
            opacitySlider.ValueChanged += UpdateOpacityLive;
            controls.Children.Add(opacitySlider);
            controls.Children.Add(ButtonOf("启用实验覆盖层", EnableOverlay));
            Button disable = ButtonOf("停止并恢复工作区", DisableOverlay);
            disable.Margin = new Thickness(0, 8, 0, 0);
            controls.Children.Add(disable);

            controls.Children.Add(Separator(22));
            syncStartupCheck = new CheckBox { Content = "同步为启动动画壁纸", IsChecked = config.syncStartupWallpaper, Foreground = Brushes.White, FontSize = 13 };
            controls.Children.Add(syncStartupCheck);
            Button save = ButtonOf("保存壁纸设置", SaveOnly);
            save.Margin = new Thickness(0, 10, 0, 0);
            controls.Children.Add(save);
            Grid.SetColumn(controls, 1);
            body.Children.Add(controls);

            status = Text("实验覆盖层当前默认关闭。", 13, new SolidColorBrush(Color.FromRgb(160, 219, 185)), FontWeights.Normal);
            status.TextWrapping = TextWrapping.Wrap;
            Grid.SetRow(status, 2);
            root.Children.Add(status);
            return root;
        }

        private Border PanelBorder()
        {
            return new Border {
                Background = new SolidColorBrush(Color.FromRgb(32, 35, 46)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(81, 87, 108)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(1),
                ClipToBounds = true
            };
        }

        private TextBlock Text(string value, double size, Brush color, FontWeight weight)
        {
            return new TextBlock { Text = value, FontSize = size, Foreground = color, FontWeight = weight };
        }

        private UIElement Separator(double top)
        {
            return new Border { Height = 1, Background = new SolidColorBrush(Color.FromRgb(71, 76, 95)), Margin = new Thickness(0, top, 0, 18) };
        }

        private Button ButtonOf(string label, RoutedEventHandler handler = null)
        {
            Button button = new Button {
                Content = label,
                Height = 38,
                Background = new SolidColorBrush(Color.FromRgb(86, 111, 156)),
                Foreground = Brushes.White,
                BorderThickness = new Thickness(0),
                FontSize = 13,
                Cursor = Cursors.Hand
            };
            if (handler != null) button.Click += handler;
            return button;
        }

        private void ChooseImage(object sender, RoutedEventArgs e)
        {
            OpenFileDialog dialog = new OpenFileDialog {
                Filter = "图片文件|*.jpg;*.jpeg;*.png;*.bmp|所有文件|*.*",
                CheckFileExists = true,
                Multiselect = false
            };
            if (dialog.ShowDialog(this) != true) return;
            try {
                string extension = IOPath.GetExtension(dialog.FileName);
                string relative = "assets\\workspace-wallpaper" + extension;
                string destination = IOPath.Combine(baseDirectory, relative);
                Directory.CreateDirectory(IOPath.GetDirectoryName(destination));
                File.Copy(dialog.FileName, destination, true);
                config.workspaceImage = relative;
                RefreshPreview();
                status.Text = "已选择壁纸。点击保存或启用后生效。";
            } catch (Exception ex) {
                status.Text = "无法复制壁纸：" + ex.Message;
            }
        }

        private void EnableOverlay(object sender, RoutedEventArgs e)
        {
            config.workspaceEnabled = true;
            SaveConfigAndOptionalStartupWallpaper();
            OverlaySignal.Stop();
            DispatcherTimer launchTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(450) };
            launchTimer.Tick += delegate {
                launchTimer.Stop();
                Process.Start(new ProcessStartInfo { FileName = Process.GetCurrentProcess().MainModule.FileName, Arguments = "--overlay", UseShellExecute = true });
            };
            launchTimer.Start();
            status.Text = "实验覆盖层已启用；切换到 Codex 前台即可显示。";
        }

        private void DisableOverlay(object sender, RoutedEventArgs e)
        {
            config.workspaceEnabled = false;
            SaveConfigAndOptionalStartupWallpaper();
            OverlaySignal.Stop();
            status.Text = "实验覆盖层已停止，Codex 原界面未被修改。";
        }

        private void SaveOnly(object sender, RoutedEventArgs e)
        {
            SaveConfigAndOptionalStartupWallpaper();
            status.Text = "壁纸设置已保存。实验覆盖层仍保持" + (config.workspaceEnabled ? "启用" : "关闭") + "。";
        }

        private void UpdateOpacityLive(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (status == null) return;
            config.workspaceOpacity = opacitySlider.Value / 100.0;
            Program.SaveConfig(configPath, config);
            status.Text = "透明度已实时更新为 " + Math.Round(opacitySlider.Value) + "% 。";
        }

        private void SaveConfigAndOptionalStartupWallpaper()
        {
            config.workspaceOpacity = opacitySlider.Value / 100.0;
            config.syncStartupWallpaper = syncStartupCheck.IsChecked == true;
            Program.SaveConfig(configPath, config);
            if (config.syncStartupWallpaper) SyncStartupWallpaper();
        }

        private void SyncStartupWallpaper()
        {
            try {
                string outputsRoot = Directory.GetParent(baseDirectory).FullName;
                string launcherDirectory = IOPath.Combine(outputsRoot, "Codex-Dream-Launcher-v0.1.0");
                string launcherConfig = IOPath.Combine(launcherDirectory, "launcher.json");
                string source = ResolvePath(config.workspaceImage);
                if (!File.Exists(launcherConfig) || !File.Exists(source)) return;
                string extension = IOPath.GetExtension(source);
                string relative = "assets\\control-center-wallpaper" + extension;
                File.Copy(source, IOPath.Combine(launcherDirectory, relative), true);
                string text = File.ReadAllText(launcherConfig, Encoding.UTF8);
                int key = text.IndexOf("\"backgroundImage\"", StringComparison.Ordinal);
                int colon = key >= 0 ? text.IndexOf(':', key) : -1;
                int quoteStart = colon >= 0 ? text.IndexOf('"', colon) : -1;
                int quoteEnd = quoteStart >= 0 ? text.IndexOf('"', quoteStart + 1) : -1;
                if (quoteStart >= 0 && quoteEnd > quoteStart) {
                    text = text.Substring(0, quoteStart + 1) + relative.Replace("\\", "\\\\") + text.Substring(quoteEnd);
                    File.WriteAllText(launcherConfig, text, new UTF8Encoding(false));
                }
            } catch (Exception ex) {
                status.Text = "工作区壁纸已保存，但未能同步启动动画：" + ex.Message;
            }
        }

        private void RefreshPreview()
        {
            string source = ResolvePath(config.workspaceImage);
            imagePathText.Text = File.Exists(source) ? source : "未找到壁纸文件";
            try {
                preview.Source = File.Exists(source) ? new BitmapImage(new Uri(source, UriKind.Absolute)) : null;
            } catch {
                preview.Source = null;
            }
        }

        private string ResolvePath(string value)
        {
            return IOPath.IsPathRooted(value) ? value : IOPath.GetFullPath(IOPath.Combine(baseDirectory, value));
        }
    }

    public static class Program
    {
        [STAThread]
        public static void Main(string[] args)
        {
            string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
            ControlConfig config = LoadConfig(IOPath.Combine(baseDirectory, "launcher.json"));
            bool overlayMode = args != null && args.Any(delegate(string value) { return string.Equals(value, "--overlay", StringComparison.OrdinalIgnoreCase); });
            Application app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            if (overlayMode) {
                if (!config.workspaceEnabled) return;
                app.Run(new OverlayWindow(config, baseDirectory));
            } else {
                app.Run(new ControlCenterWindow(baseDirectory));
            }
        }

        internal static ControlConfig LoadConfig(string path)
        {
            ControlConfig fallback = ControlConfig.Defaults();
            if (!File.Exists(path)) return fallback;
            try {
                DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(ControlConfig));
                using (FileStream stream = File.OpenRead(path)) {
                    ControlConfig loaded = serializer.ReadObject(stream) as ControlConfig;
                    if (loaded == null) return fallback;
                    if (string.IsNullOrWhiteSpace(loaded.workspaceImage)) loaded.workspaceImage = fallback.workspaceImage;
                    if (loaded.workspaceOpacity < 0.01 || loaded.workspaceOpacity > 0.10) loaded.workspaceOpacity = fallback.workspaceOpacity;
                    if (string.IsNullOrWhiteSpace(loaded.targetProcess)) loaded.targetProcess = fallback.targetProcess;
                    return loaded;
                }
            } catch {
                return fallback;
            }
        }

        internal static void SaveConfig(string path, ControlConfig config)
        {
            DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(ControlConfig));
            using (FileStream stream = File.Create(path)) serializer.WriteObject(stream, config);
        }
    }
}
