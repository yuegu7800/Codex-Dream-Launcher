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
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using IOPath = System.IO.Path;

namespace CodexDreamLauncher
{
    [DataContract]
    public sealed class LauncherConfig
    {
        [DataMember] public string brand;
        [DataMember] public string subtitle;
        [DataMember] public string backgroundImage;
        [DataMember] public bool coverScreen;
        [DataMember] public string appUserModelId;
        [DataMember] public string targetProcess;
        [DataMember] public int minimumDisplayMilliseconds;
        [DataMember] public int maximumWaitMilliseconds;
        [DataMember] public string[] statusMessages;
        [DataMember] public string[] readyText;

        public static LauncherConfig Defaults()
        {
            return new LauncherConfig {
                brand = "CODEX DREAM",
                subtitle = "PERSONAL LAUNCH SEQUENCE",
                backgroundImage = "assets\\violet-evergarden.jpg",
                coverScreen = true,
                appUserModelId = "OpenAI.Codex_2p2nqsd0c76g0!App",
                targetProcess = "ChatGPT",
                minimumDisplayMilliseconds = 2200,
                maximumWaitMilliseconds = 40000,
                statusMessages = new[] { "INITIALIZING WORKSPACE", "LOCATING CODEX", "PREPARING SESSION", "WAITING FOR CODEX HOME" },
                readyText = new[] { "我们要构建什么", "What would you like to build" }
            };
        }
    }

    internal static class NativeMethods
    {
        internal delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")] internal static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] internal static extern bool IsHungAppWindow(IntPtr hWnd);
        [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] internal static extern bool ShowWindow(IntPtr hWnd, int command);
        [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr hWnd, out RectNative rect);

        [StructLayout(LayoutKind.Sequential)]
        internal struct RectNative { internal int Left, Top, Right, Bottom; }

        internal const int RestoreWindow = 9;
    }

    public sealed class SplashWindow : Window
    {
        private readonly LauncherConfig config;
        private readonly string baseDirectory;
        private readonly string logPath;
        private readonly bool previewMode;
        private readonly Stopwatch elapsed = Stopwatch.StartNew();
        private readonly DispatcherTimer pollTimer;
        private readonly DispatcherTimer messageTimer;
        private TextBlock statusText;
        private Border progressBar;
        private int messageIndex;
        private IntPtr targetWindow = IntPtr.Zero;
        private DateTime? targetFirstSeen;
        private bool closing;

        public SplashWindow(LauncherConfig config, string baseDirectory, bool previewMode)
        {
            this.config = config;
            this.baseDirectory = baseDirectory;
            this.logPath = IOPath.Combine(baseDirectory, "launcher.log");
            this.previewMode = previewMode;

            if (config.coverScreen) {
                Left = SystemParameters.VirtualScreenLeft;
                Top = SystemParameters.VirtualScreenTop;
                Width = SystemParameters.VirtualScreenWidth;
                Height = SystemParameters.VirtualScreenHeight;
                WindowStartupLocation = WindowStartupLocation.Manual;
            } else {
                Width = 900;
                Height = 560;
                MinWidth = 760;
                MinHeight = 470;
                WindowStartupLocation = WindowStartupLocation.CenterScreen;
            }
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = true;
            Opacity = 0;

            Content = BuildLayout();
            Loaded += OnLoaded;
            KeyDown += OnKeyDown;
            MouseLeftButtonDown += delegate { try { DragMove(); } catch { } };

            pollTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            pollTimer.Tick += PollForTarget;
            messageTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1350) };
            messageTimer.Tick += RotateMessage;
        }

        private UIElement BuildLayout()
        {
            Border frame = new Border {
                CornerRadius = new CornerRadius(8),
                BorderThickness = new Thickness(1),
                BorderBrush = new SolidColorBrush(Color.FromArgb(135, 204, 220, 255)),
                Background = new SolidColorBrush(Color.FromRgb(18, 20, 28)),
                ClipToBounds = true
            };

            Grid root = new Grid();
            frame.Child = root;

            string imagePath = ResolvePath(config.backgroundImage);
            if (File.Exists(imagePath)) {
                root.Background = new ImageBrush(new BitmapImage(new Uri(imagePath, UriKind.Absolute))) {
                    Stretch = Stretch.UniformToFill,
                    AlignmentX = AlignmentX.Center,
                    AlignmentY = AlignmentY.Center
                };
            }

            Border contrast = new Border {
                Background = new LinearGradientBrush(
                    Color.FromArgb(232, 17, 20, 29),
                    Color.FromArgb(70, 17, 20, 29),
                    new Point(0, 0.5), new Point(1, 0.5))
            };
            root.Children.Add(contrast);

            if (config.coverScreen) {
                root.Children.Add(new Border {
                    Background = new SolidColorBrush(Color.FromArgb(20, 8, 10, 17))
                });
            }

            Grid content = new Grid { Margin = config.coverScreen ? new Thickness(70, 58, 70, 48) : new Thickness(42) };
            content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.Children.Add(content);

            Grid header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition());
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            TextBlock mark = new TextBlock {
                Text = "CD / 01",
                Foreground = new SolidColorBrush(Color.FromRgb(205, 224, 255)),
                FontFamily = new FontFamily("Segoe UI Semibold"),
                FontSize = 12
            };
            header.Children.Add(mark);
            Button close = new Button {
                Content = "×",
                Width = 34,
                Height = 34,
                FontSize = 19,
                Foreground = Brushes.White,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Cursor = Cursors.Hand,
                ToolTip = "Close splash"
            };
            close.Click += delegate { CloseSplash(false); };
            Grid.SetColumn(close, 1);
            header.Children.Add(close);
            Grid.SetRow(header, 0);
            content.Children.Add(header);

            Grid center = new Grid { Width = 420, HorizontalAlignment = HorizontalAlignment.Left };
            center.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            center.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            center.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Canvas signal = BuildSignal();
            signal.Margin = new Thickness(0, 0, 0, 28);
            Grid.SetRow(signal, 0);
            center.Children.Add(signal);

            StackPanel identity = new StackPanel();
            TextBlock brand = new TextBlock {
                Text = config.brand,
                Foreground = Brushes.White,
                FontFamily = new FontFamily("Segoe UI Light"),
                FontSize = 43,
                FontWeight = FontWeights.Light
            };
            TextBlock subtitle = new TextBlock {
                Text = config.subtitle,
                Margin = new Thickness(2, 8, 0, 0),
                Foreground = new SolidColorBrush(Color.FromRgb(187, 201, 225)),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12
            };
            identity.Children.Add(brand);
            identity.Children.Add(subtitle);
            Grid.SetRow(identity, 1);
            center.Children.Add(identity);

            StackPanel statusPanel = new StackPanel { Margin = new Thickness(2, 34, 0, 0) };
            statusText = new TextBlock {
                Text = FirstMessage(),
                Foreground = new SolidColorBrush(Color.FromRgb(225, 233, 248)),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12
            };
            Border track = new Border {
                Width = 250,
                Height = 2,
                Margin = new Thickness(0, 14, 0, 0),
                HorizontalAlignment = HorizontalAlignment.Left,
                Background = new SolidColorBrush(Color.FromArgb(75, 225, 233, 248)),
                ClipToBounds = true
            };
            progressBar = new Border {
                Width = 78,
                Height = 2,
                HorizontalAlignment = HorizontalAlignment.Left,
                Background = new SolidColorBrush(Color.FromRgb(136, 224, 161)),
                RenderTransform = new TranslateTransform(-78, 0)
            };
            track.Child = progressBar;
            statusPanel.Children.Add(statusText);
            statusPanel.Children.Add(track);
            Grid.SetRow(statusPanel, 2);
            center.Children.Add(statusPanel);

            Grid.SetRow(center, 1);
            content.Children.Add(center);

            TextBlock footer = new TextBlock {
                Text = "ESC  DISMISS SPLASH    •    OFFICIAL APP REMAINS UNMODIFIED",
                Foreground = new SolidColorBrush(Color.FromArgb(185, 210, 220, 238)),
                FontFamily = new FontFamily("Consolas"),
                FontSize = 10
            };
            Grid.SetRow(footer, 2);
            content.Children.Add(footer);

            return frame;
        }

        private Canvas BuildSignal()
        {
            Canvas canvas = new Canvas { Width = 86, Height = 86, HorizontalAlignment = HorizontalAlignment.Left };
            Ellipse outer = new Ellipse {
                Width = 84, Height = 84,
                Stroke = new SolidColorBrush(Color.FromArgb(145, 181, 178, 215)),
                StrokeThickness = 1,
                StrokeDashArray = new DoubleCollection(new[] { 7.0, 10.0 }),
                RenderTransformOrigin = new Point(0.5, 0.5)
            };
            RotateTransform rotation = new RotateTransform();
            outer.RenderTransform = rotation;
            rotation.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(9)) {
                RepeatBehavior = RepeatBehavior.Forever
            });
            canvas.Children.Add(outer);

            Ellipse inner = new Ellipse {
                Width = 46, Height = 46,
                Stroke = new SolidColorBrush(Color.FromArgb(210, 136, 224, 161)),
                StrokeThickness = 1
            };
            Canvas.SetLeft(inner, 19);
            Canvas.SetTop(inner, 19);
            canvas.Children.Add(inner);

            Ellipse core = new Ellipse {
                Width = 9, Height = 9,
                Fill = new SolidColorBrush(Color.FromRgb(251, 237, 241))
            };
            Canvas.SetLeft(core, 37.5);
            Canvas.SetTop(core, 37.5);
            canvas.Children.Add(core);

            return canvas;
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(320)));
            StartProgressAnimation();
            WriteLog("Launcher started.");
            if (previewMode) {
                statusText.Text = "PREVIEW MODE  •  ESC TO CLOSE";
                return;
            }
            LaunchOrActivate();
            pollTimer.Start();
            messageTimer.Start();
        }

        private void StartProgressAnimation()
        {
            TranslateTransform transform = progressBar.RenderTransform as TranslateTransform;
            if (transform == null) return;
            transform.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-78, 250, TimeSpan.FromSeconds(1.45)) {
                RepeatBehavior = RepeatBehavior.Forever
            });
        }

        private void LaunchOrActivate()
        {
            targetWindow = FindTargetWindow();
            if (targetWindow != IntPtr.Zero) {
                WriteLog("Existing Codex window found.");
                ActivateTarget(targetWindow);
                targetFirstSeen = DateTime.UtcNow;
                statusText.Text = "CODEX WINDOW FOUND";
                return;
            }

            try {
                Process.Start(new ProcessStartInfo {
                    FileName = "explorer.exe",
                    Arguments = "shell:AppsFolder\\" + config.appUserModelId,
                    UseShellExecute = true
                });
                WriteLog("Store activation requested for " + config.appUserModelId + ".");
                statusText.Text = "STARTING OFFICIAL APP";
            } catch (Exception ex) {
                WriteLog("Activation request failed: " + ex.Message);
                statusText.Text = "APP START REQUEST FAILED";
            }
        }

        private void PollForTarget(object sender, EventArgs e)
        {
            if (closing) return;
            IntPtr found = FindTargetWindow();
            if (found != IntPtr.Zero) {
                if (targetWindow != found) {
                    targetWindow = found;
                    targetFirstSeen = DateTime.UtcNow;
                    WriteLog("Responsive Codex window detected.");
                }

                bool textReady = HasReadyText(targetWindow);
                if (textReady && elapsed.ElapsedMilliseconds >= config.minimumDisplayMilliseconds) {
                    statusText.Text = "READY";
                    WriteLog("Codex home prompt detected through Windows accessibility.");
                    ActivateTarget(targetWindow);
                    CloseSplash(true);
                    return;
                }

                if (targetFirstSeen.HasValue && (DateTime.UtcNow - targetFirstSeen.Value).TotalSeconds >= 2) {
                    statusText.Text = "WAITING FOR CODEX HOME";
                }
            }

            if (elapsed.ElapsedMilliseconds >= config.maximumWaitMilliseconds) {
                statusText.Text = "CODEX IS STILL STARTING";
                WriteLog("Window readiness timeout reached; closing splash without terminating Codex.");
                pollTimer.Stop();
                messageTimer.Stop();
                DispatcherTimer exitTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) };
                exitTimer.Tick += delegate { exitTimer.Stop(); CloseSplash(false); };
                exitTimer.Start();
            }
        }

        private IntPtr FindTargetWindow()
        {
            HashSet<int> targetIds = new HashSet<int>();
            string processName = string.IsNullOrWhiteSpace(config.targetProcess) ? "ChatGPT" : config.targetProcess;
            foreach (Process process in Process.GetProcessesByName(processName)) {
                try { targetIds.Add(process.Id); } catch { }
            }
            if (targetIds.Count == 0) return IntPtr.Zero;

            IntPtr best = IntPtr.Zero;
            int bestArea = 0;
            NativeMethods.EnumWindows(delegate(IntPtr window, IntPtr ignored) {
                if (!NativeMethods.IsWindowVisible(window) || NativeMethods.IsHungAppWindow(window)) return true;
                uint processId;
                NativeMethods.GetWindowThreadProcessId(window, out processId);
                if (!targetIds.Contains((int)processId)) return true;
                NativeMethods.RectNative rect;
                if (!NativeMethods.GetWindowRect(window, out rect)) return true;
                int width = Math.Max(0, rect.Right - rect.Left);
                int height = Math.Max(0, rect.Bottom - rect.Top);
                int area = width * height;
                if (width >= 500 && height >= 350 && area > bestArea) {
                    best = window;
                    bestArea = area;
                }
                return true;
            }, IntPtr.Zero);
            return best;
        }

        private void ActivateTarget(IntPtr window)
        {
            if (window == IntPtr.Zero) return;
            try {
                NativeMethods.ShowWindow(window, NativeMethods.RestoreWindow);
                NativeMethods.SetForegroundWindow(window);
            } catch { }
        }

        // Read-only UI Automation check. This only observes the official window; it does not inject or alter Codex.
        private bool HasReadyText(IntPtr window)
        {
            if (window == IntPtr.Zero || config.readyText == null || config.readyText.Length == 0) return false;
            try {
                AutomationElement root = AutomationElement.FromHandle(window);
                if (root == null) return false;
                AutomationElementCollection textElements = root.FindAll(TreeScope.Descendants,
                    new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Text));
                foreach (AutomationElement element in textElements) {
                    string name = element.Current.Name;
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    foreach (string expected in config.readyText) {
                        if (!string.IsNullOrWhiteSpace(expected) &&
                            name.IndexOf(expected, StringComparison.OrdinalIgnoreCase) >= 0) return true;
                    }
                }
            } catch (ElementNotAvailableException) {
            } catch (InvalidOperationException) {
            }
            return false;
        }

        private void RotateMessage(object sender, EventArgs e)
        {
            if (config.statusMessages == null || config.statusMessages.Length == 0) return;
            messageIndex = (messageIndex + 1) % config.statusMessages.Length;
            statusText.Text = config.statusMessages[messageIndex];
        }

        private string FirstMessage()
        {
            return config.statusMessages != null && config.statusMessages.Length > 0
                ? config.statusMessages[0]
                : "INITIALIZING WORKSPACE";
        }

        private string ResolvePath(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return string.Empty;
            return IOPath.IsPathRooted(value) ? value : IOPath.GetFullPath(IOPath.Combine(baseDirectory, value));
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape) CloseSplash(false);
        }

        private void CloseSplash(bool ready)
        {
            if (closing) return;
            closing = true;
            pollTimer.Stop();
            messageTimer.Stop();
            WriteLog(ready ? "Codex ready; splash closing." : "Splash dismissed.");
            DoubleAnimation fade = new DoubleAnimation(Opacity, 0, TimeSpan.FromMilliseconds(280));
            fade.Completed += delegate { Close(); };
            BeginAnimation(OpacityProperty, fade);
        }

        private void WriteLog(string message)
        {
            try {
                File.AppendAllText(logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message + Environment.NewLine, Encoding.UTF8);
            } catch { }
        }
    }

    public static class Program
    {
        [STAThread]
        public static void Main(string[] args)
        {
            bool created;
            using (Mutex mutex = new Mutex(true, "Local\\CodexDreamLauncher.Personal", out created)) {
                if (!created) return;
                string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
                LauncherConfig config = LoadConfig(IOPath.Combine(baseDirectory, "launcher.json"));
                bool previewMode = args != null && args.Any(delegate(string value) {
                    return string.Equals(value, "--preview", StringComparison.OrdinalIgnoreCase);
                });
                Application app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
                app.Run(new SplashWindow(config, baseDirectory, previewMode));
            }
        }

        private static LauncherConfig LoadConfig(string path)
        {
            LauncherConfig fallback = LauncherConfig.Defaults();
            if (!File.Exists(path)) return fallback;
            try {
                DataContractJsonSerializer serializer = new DataContractJsonSerializer(typeof(LauncherConfig));
                using (FileStream stream = File.OpenRead(path)) {
                    LauncherConfig loaded = serializer.ReadObject(stream) as LauncherConfig;
                    if (loaded == null) return fallback;
                    if (string.IsNullOrWhiteSpace(loaded.brand)) loaded.brand = fallback.brand;
                    if (string.IsNullOrWhiteSpace(loaded.subtitle)) loaded.subtitle = fallback.subtitle;
                    if (string.IsNullOrWhiteSpace(loaded.backgroundImage)) loaded.backgroundImage = fallback.backgroundImage;
                    if (string.IsNullOrWhiteSpace(loaded.appUserModelId)) loaded.appUserModelId = fallback.appUserModelId;
                    if (string.IsNullOrWhiteSpace(loaded.targetProcess)) loaded.targetProcess = fallback.targetProcess;
                    if (loaded.minimumDisplayMilliseconds < 300) loaded.minimumDisplayMilliseconds = fallback.minimumDisplayMilliseconds;
                    if (loaded.maximumWaitMilliseconds < loaded.minimumDisplayMilliseconds) loaded.maximumWaitMilliseconds = fallback.maximumWaitMilliseconds;
                    if (loaded.statusMessages == null || loaded.statusMessages.Length == 0) loaded.statusMessages = fallback.statusMessages;
                    if (loaded.readyText == null || loaded.readyText.Length == 0) loaded.readyText = fallback.readyText;
                    return loaded;
                }
            } catch {
                return fallback;
            }
        }
    }
}
