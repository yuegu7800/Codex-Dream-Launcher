param([string[]]$LibraryRoot=@())
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Transfer.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
$toolRoot=$PSScriptRoot
$exportRoot=Join-Path $toolRoot 'data\exports'
$script:catalog=@(); $script:worker=$null; $script:pending=$null
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Dragon · Wallpaper 本地素材库" Width="1100" Height="740" MinWidth="900" MinHeight="600" Background="#F3F5F8" WindowStartupLocation="CenterScreen">
 <Grid Margin="24">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel><TextBlock Text="Wallpaper Engine 本地库" FontSize="26" FontWeight="SemiBold"/><TextBlock Text="独立正式版 · 读取本地素材 · 自动加入正式版素材库 · 手动应用" Foreground="#596174" Margin="0,8,0,18"/></StackPanel>
  <DockPanel Grid.Row="1" Margin="0,0,0,14"><Button Name="Refresh" Content="自动扫描" Padding="14,7" Margin="0,0,8,0"/><Button Name="AddFolder" Content="添加库目录…" Padding="14,7" Margin="0,0,8,0"/><TextBox Name="Search" MinWidth="180" Padding="8" ToolTip="按标题、ID、类型或标签搜索"/></DockPanel>
  <Grid Grid.Row="2"><Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
   <DataGrid Name="List" IsReadOnly="True" AutoGenerateColumns="False" SelectionMode="Single" CanUserAddRows="False" HeadersVisibility="Column" Background="White" BorderBrush="#D6DCE6"><DataGrid.Columns><DataGridTextColumn Header="标题" Binding="{Binding Title}" Width="*"/><DataGridTextColumn Header="类型" Binding="{Binding Type}" Width="65"/><DataGridTextColumn Header="MiB" Binding="{Binding MiB}" Width="60"/><DataGridCheckBoxColumn Header="可导出" Binding="{Binding Compatible}" Width="60"/></DataGrid.Columns></DataGrid>
   <Grid Grid.Column="1" Margin="20,0,0,0"><Grid.RowDefinitions><RowDefinition Height="210"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid Background="#E3E7EE"><Image Name="Preview" Stretch="Uniform"/><MediaElement Name="Video" LoadedBehavior="Manual" UnloadedBehavior="Close" Volume="0" Visibility="Collapsed"/></Grid>
    <TextBlock Name="Title" Grid.Row="1" FontSize="19" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,14,0,10" Text="选择一张壁纸"/>
    <TextBox Name="Details" Grid.Row="2" IsReadOnly="True" TextWrapping="Wrap" Background="Transparent" BorderThickness="0" VerticalScrollBarVisibility="Auto"/>
    <StackPanel Grid.Row="3"><Button Name="Play" Content="静音预览 / 停止" Padding="12,9" Margin="0,8,0,8" IsEnabled="False"/><Button Name="Export" Content="导出并加入正式版素材库" Padding="12,9" IsEnabled="False"/><Button Name="Convert" Content="转换并加入素材库（最长 30 秒）" Padding="12,9" Margin="0,8,0,0" IsEnabled="False"/><Button Name="Manager" Content="打开正式版主题管理器" Padding="12,9" Margin="0,8,0,0"/><TextBlock Text="导出/转换后自动加入正式版管理器的素材列表。需手动应用；不会自动切换当前主题。" Foreground="#596174" TextWrapping="Wrap" Margin="0,10,0,0"/></StackPanel>
   </Grid>
  </Grid>
  <TextBlock Name="Status" Grid.Row="3" Text="正在准备扫描…" Foreground="#596174" Margin="0,16,0,0" TextWrapping="Wrap"/>
 </Grid>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
$controls=@{}; foreach($name in @('Refresh','AddFolder','Search','List','Preview','Video','Title','Details','Play','Export','Convert','Manager','Status')) {$controls[$name]=$window.FindName($name)}
$script:extraRoots=@($LibraryRoot)
$settingsPath=Join-Path $toolRoot 'data\roots.json'
if(Test-Path -LiteralPath $settingsPath){try{$script:extraRoots+=@([IO.File]::ReadAllText($settingsPath)|ConvertFrom-Json)}catch{}}
function Update-List {
 $query=$controls.Search.Text
 $filtered=@($script:catalog|Where-Object{!$query -or ($_.Title+' '+$_.Id+' '+$_.Type+' '+$_.Tags).IndexOf($query,[StringComparison]::OrdinalIgnoreCase)-ge 0})
 $controls.List.ItemsSource=$filtered
 $controls.Status.Text="匹配 $($filtered.Count) / 共 $($script:catalog.Count) 张。MP4 可导出；图片/GIF/视频可转换；纯场景与网页暂不播放。"
}
function Start-Scan {
 if($script:worker){return}
 $controls.Refresh.IsEnabled=$false; $controls.AddFolder.IsEnabled=$false
 $controls.Status.Text='正在后台扫描 Steam 多个素材库…'
 $script:worker=[PowerShell]::Create()
 $null=$script:worker.AddScript('param($scriptPath,$extra); . $scriptPath; Read-WallpaperCatalog @(Get-WallpaperRoots $extra)').AddArgument((Join-Path $toolRoot 'Library.ps1')).AddArgument($script:extraRoots)
 $script:pending=$script:worker.BeginInvoke()
}
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
 if($script:worker -and $script:pending.IsCompleted){
  try{$result=@($script:worker.EndInvoke($script:pending)); if($script:transfer){if($script:worker.HadErrors){throw ($script:worker.Streams.Error -join "`n")}; $controls.Status.Text="已加入正式版素材库。打开正式版管理器，在视频素材中选择；不会自动应用。"}else{$script:catalog=$result; Update-List}; if($script:worker.HadErrors){$controls.Status.Text+=' 部分目录读取失败。'}}catch{$controls.Status.Text=$_.Exception.Message}
  finally{$script:worker.Dispose();$script:worker=$null;$script:transfer=$false;$controls.Refresh.IsEnabled=$true;$controls.AddFolder.IsEnabled=$true;$item=$controls.List.SelectedItem;$controls.Export.IsEnabled=($null-ne $item -and $item.Compatible);$controls.Convert.IsEnabled=($null-ne $item -and $item.Convertible)}
 }
})
$controls.Refresh.Add_Click({Start-Scan})
$controls.Search.Add_TextChanged({Update-List})
$controls.AddFolder.Add_Click({
 $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
 $dialog.Description='选择 431960 素材库、myprojects 目录，或单张壁纸目录'
 try {if($dialog.ShowDialog()-eq [System.Windows.Forms.DialogResult]::OK){
  $script:extraRoots+=Assert-LocalPath $dialog.SelectedPath
  New-Item -ItemType Directory -Path (Split-Path $settingsPath -Parent) -Force|Out-Null
  [IO.File]::WriteAllText($settingsPath,(ConvertTo-Json -InputObject @($script:extraRoots|Select-Object -Unique)),[Text.UTF8Encoding]::new($false))
  Start-Scan
 }}catch{[Windows.MessageBox]::Show($_.Exception.Message)|Out-Null}finally{$dialog.Dispose()}
})
$controls.List.Add_SelectionChanged({
 $controls.Video.Stop();$controls.Video.Source=$null;$controls.Video.Visibility='Collapsed';$controls.Preview.Source=$null
 $item=$controls.List.SelectedItem
 $controls.Play.IsEnabled=($null-ne $item -and $item.Compatible);$controls.Export.IsEnabled=$controls.Play.IsEnabled; $controls.Convert.IsEnabled=($null-ne $item -and $item.Convertible)
 if(!$item){return}
 $controls.Title.Text=$item.Title
 $controls.Details.Text="ID: $($item.Id)`n类型: $($item.Type)`n大小: $($item.MiB) MiB`n`n$($item.Reason)`n`n$($item.Media)"
 if($item.Preview){try{
  $bitmap=New-Object Windows.Media.Imaging.BitmapImage
  $bitmap.BeginInit();$bitmap.CacheOption='OnLoad';$bitmap.DecodePixelWidth=480;$bitmap.UriSource=[uri]$item.Preview;$bitmap.EndInit();$bitmap.Freeze();$controls.Preview.Source=$bitmap
 }catch{$controls.Status.Text='预览图解码失败；仍可查看媒体信息。'}}
})
$controls.Play.Add_Click({
 if($controls.Video.Visibility-eq 'Visible'){$controls.Video.Stop();$controls.Video.Source=$null;$controls.Video.Visibility='Collapsed';return}
 $item=$controls.List.SelectedItem
 if($item -and $item.Compatible){$controls.Video.Source=[uri](Assert-LocalPath $item.Media);$controls.Video.Visibility='Visible';$controls.Video.Play()}
})
$controls.Video.Add_MediaEnded({$controls.Video.Position=[TimeSpan]::Zero;$controls.Video.Play()})
$controls.Video.Add_MediaFailed({$controls.Video.Stop();$controls.Video.Visibility='Collapsed';$controls.Status.Text='视频解码失败，请使用 Windows 可播放的 H.264 MP4。'})
function Start-Transfer([bool]$Convert) {
 if($script:worker){return}
 $item=$controls.List.SelectedItem
 if(!$item){return}
 $script:transfer=$true
 $controls.Refresh.IsEnabled=$false; $controls.AddFolder.IsEnabled=$false
 $controls.Export.IsEnabled=$false; $controls.Convert.IsEnabled=$false
 $controls.Status.Text='正在复制/转换并加入正式版素材库… 转换最多 120 秒。'
 $script:worker=[PowerShell]::Create()
 $null=$script:worker.AddScript('param($p,$item,$convert); . $p; Send-WallpaperToExperiment $item $convert').AddArgument((Join-Path $toolRoot 'Transfer.ps1')).AddArgument($item).AddArgument($Convert)
 $script:pending=$script:worker.BeginInvoke()
}
$controls.Export.Add_Click({Start-Transfer $false})
$controls.Convert.Add_Click({Start-Transfer $true})
$controls.Manager.Add_Click({
 try {
  $manager=Join-Path (Split-Path $toolRoot -Parent) 'DragonStudio.exe'
  if(!(Test-Path -LiteralPath $manager)){throw '正式版管理器尚未构建。'}
  Start-Process -FilePath $manager
 }catch{[Windows.MessageBox]::Show($_.Exception.Message)|Out-Null}
})
$window.Add_Closed({$timer.Stop();$controls.Video.Stop();if($script:worker){$script:worker.Stop();$script:worker.Dispose()}})
$window.Add_StateChanged({if($window.WindowState-eq 'Minimized'){$controls.Video.Pause()}})
$timer.Start();Start-Scan
$null=$window.ShowDialog()
