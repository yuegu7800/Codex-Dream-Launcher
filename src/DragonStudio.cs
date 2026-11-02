using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using Forms=System.Windows.Forms;

public sealed class DragonStudio {
 sealed class Item { public string Name {get;set;} public string Id {get;set;} public string Path {get;set;} public double Opacity {get;set;} public string Accent {get;set;} public string Panel {get;set;} public string Background {get;set;} }
 string root; Window window; ComboBox videos,presets; MediaElement preview; Slider reveal; TextBlock status;
 Forms.NotifyIcon tray; bool quitting,busy;
 JavaScriptSerializer json=new JavaScriptSerializer();
 DragonStudio(string root) {
  this.root=root;
  using(var reader=System.Xml.XmlReader.Create(System.IO.Path.Combine(root,"scripts","manager-window.xaml"))) window=(Window)XamlReader.Load(reader);
  videos=(ComboBox)window.FindName("Videos");presets=(ComboBox)window.FindName("Presets");preview=(MediaElement)window.FindName("Preview");reveal=(Slider)window.FindName("Reveal");status=(TextBlock)window.FindName("Status");
  videos.SelectionChanged+=(s,e)=>{var item=videos.SelectedItem as Item;if(item!=null){preview.Stop();preview.Source=new Uri(item.Path);if(window.IsVisible)preview.Play();}};
  presets.SelectionChanged+=(s,e)=>{var item=presets.SelectedItem as Item;if(item!=null){var converter=new System.Windows.Media.BrushConverter();((System.Windows.Controls.Border)window.FindName("AccentSwatch")).Background=(System.Windows.Media.Brush)converter.ConvertFromString(item.Accent);((System.Windows.Controls.Border)window.FindName("PanelSwatch")).Background=(System.Windows.Media.Brush)converter.ConvertFromString(item.Panel);((System.Windows.Controls.Border)window.FindName("BackgroundSwatch")).Background=(System.Windows.Media.Brush)converter.ConvertFromString(item.Background);}};
  reveal.ValueChanged+=(s,e)=>((TextBlock)window.FindName("RevealLabel")).Text="壁纸透出 · "+(int)reveal.Value+"%";
  preview.MediaEnded+=(s,e)=>{preview.Position=TimeSpan.Zero;preview.Play();};
  preview.MediaFailed+=(s,e)=>status.Text="预览解码失败，请使用 H.264 MP4。当前主题未更改。";
  Button("Apply",async()=>{var v=videos.SelectedItem as Item;var p=presets.SelectedItem as Item;if(v==null||p==null)throw new Exception("请选择视频和预设");await Run("Apply","-VideoId",v.Id,"-PresetId",p.Id,"-Reveal",((int)reveal.Value).ToString());status.Text="主题已验证并保存，壁纸引擎将自动读取。";});
  Button("Import",async()=>{var d=new Microsoft.Win32.OpenFileDialog{Filter="MP4 视频（最大 16 MiB）|*.mp4"};if(d.ShowDialog(window)==true){var result=await Run("Import","-Path",d.FileName);await Refresh();videos.SelectedItem=((IEnumerable<Item>)videos.ItemsSource).FirstOrDefault(x=>x.Id==(string)result["id"]);status.Text="已添加到本地库。请先预览，再手动应用。";}});
  Button("Pause",()=>Action("Pause","壁纸已暂停；调试端口仍在，完全退出 Codex 才会关闭。"));
  Button("Resume",()=>Action("Resume","已请求恢复壁纸。"));
  Button("Normal",()=>Action("Normal","下次使用普通模式。请保存工作，完全退出 Codex 后重新打开。"));
  Button("Wallpaper",()=>Action("Wallpaper","下次使用壁纸模式。请保存工作，完全退出 Codex 后重新打开。"));
  Button("Gallery",()=>{Process.Start(new ProcessStartInfo("https://dreamskin.cc/gallery"){UseShellExecute=true});return Task.FromResult(0);});
  Button("Studio",()=>{Process.Start(new ProcessStartInfo("https://dreamskin.cc/studio"){UseShellExecute=true});return Task.FromResult(0);});
  Button("Hide",()=>{window.Hide();return Task.FromResult(0);});

  tray=new Forms.NotifyIcon{Icon=System.Drawing.SystemIcons.Application,Text="Dragon Studio · 主题管理",Visible=true};
  var menu=new Forms.ContextMenuStrip();menu.Items.Add("打开主题管理器",null,(s,e)=>Show());menu.Items.Add("暂停壁纸",null,async(s,e)=>await Safe(()=>Action("Pause","壁纸已暂停。")));menu.Items.Add("恢复壁纸",null,async(s,e)=>await Safe(()=>Action("Resume","已请求恢复。")));menu.Items.Add(new Forms.ToolStripSeparator());menu.Items.Add("退出管理器（保留壁纸）",null,(s,e)=>{quitting=true;window.Close();});tray.ContextMenuStrip=menu;tray.DoubleClick+=(s,e)=>Show();
  window.Closing+=(s,e)=>{if(!quitting){e.Cancel=true;window.Hide();}};
  window.IsVisibleChanged+=(s,e)=>{if(window.IsVisible)preview.Play();else preview.Pause();};
  window.Loaded+=async(s,e)=>await Safe(async()=>{await Refresh();preview.Play();});
  window.Activated+=async(s,e)=>await Safe(async()=>{await Refresh();});
  window.Closed+=(s,e)=>{preview.Stop();tray.Visible=false;tray.Dispose();};
 }
 void Show(){window.Show();window.WindowState=WindowState.Normal;window.Activate();}
 void Button(string name,Func<Task> action){((Button)window.FindName(name)).Click+=async(s,e)=>await Safe(action);}
 async Task Safe(Func<Task> action){if(busy)return;busy=true;try{await action();}catch(Exception e){status.Text="操作未完成："+e.Message;}finally{busy=false;}}
 async Task Action(string action,string message){await Run(action);status.Text=message;}
 async Task Refresh(){string keepVideo=videos.SelectedItem is Item?((Item)videos.SelectedItem).Id:null; string keepPreset=presets.SelectedItem is Item?((Item)presets.SelectedItem).Id:null;double keepReveal=reveal.Value;var data=await Run("List");videos.ItemsSource=Items(data["videos"]);presets.ItemsSource=Items(data["presets"]);videos.SelectedIndex=0;presets.SelectedIndex=0;
  string saved=System.IO.Path.Combine(root,"skin","library","selection.json");if(File.Exists(saved)){var d=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(saved));var v=((IEnumerable<Item>)videos.ItemsSource).FirstOrDefault(x=>x.Id==(string)d["videoId"]);var p=((IEnumerable<Item>)presets.ItemsSource).FirstOrDefault(x=>x.Id==(string)d["presetId"]);if(v!=null)videos.SelectedItem=v;if(p!=null)presets.SelectedItem=p;reveal.Value=Convert.ToDouble(d["reveal"]);}
 if(keepVideo!=null){var v=((IEnumerable<Item>)videos.ItemsSource).FirstOrDefault(x=>x.Id==keepVideo);var p=((IEnumerable<Item>)presets.ItemsSource).FirstOrDefault(x=>x.Id==keepPreset);if(v!=null)videos.SelectedItem=v;if(p!=null)presets.SelectedItem=p;reveal.Value=keepReveal;}}
 List<Item> Items(object raw){var result=new List<Item>();foreach(Dictionary<string,object> d in (ArrayList)raw)result.Add(new Item{Name=(string)d["Name"],Id=(string)d["Id"],Path=d.ContainsKey("Path")?(string)d["Path"]:null,Opacity=d.ContainsKey("Opacity")?Convert.ToDouble(d["Opacity"]):.9,Accent=d.ContainsKey("Accent")?(string)d["Accent"]:"#7468bd",Panel=d.ContainsKey("Panel")?(string)d["Panel"]:"#f8f9fd",Background=d.ContainsKey("Background")?(string)d["Background"]:"#eef1f8"});return result;}
 static string Quote(string text){if(text.IndexOf('"')>=0||text.IndexOf('\r')>=0||text.IndexOf('\n')>=0)throw new Exception("参数含无效字符");return "\""+text+"\"";}
 Task<Dictionary<string,object>> Run(string action,params string[] args){return Task.Run(()=>{
  string script=System.IO.Path.Combine(root,"scripts","Manager-Action.ps1");
  string line="-NoProfile -ExecutionPolicy Bypass -File "+Quote(script)+" -Action "+Quote(action);
  for(int i=0;i<args.Length;i+=2)line+=" "+args[i]+" "+Quote(args[i+1]);
  var info=new ProcessStartInfo(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell","v1.0","powershell.exe"),line){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
  using(var p=Process.Start(info)){var error=p.StandardError.ReadToEndAsync();string output=p.StandardOutput.ReadToEnd();p.WaitForExit();if(p.ExitCode!=0)throw new Exception(error.Result);return json.Deserialize<Dictionary<string,object>>(output);}
 });}
 [STAThread] public static int Main(){bool owns;using(var mutex=new Mutex(true,"Local\\DragonStudioNative."+System.Security.Principal.WindowsIdentity.GetCurrent().User.Value,out owns)){if(!owns){Forms.MessageBox.Show("主题管理器已在托盘运行，请双击托盘图标。","Dragon Studio");return 0;}try{var app=new Application();var studio=new DragonStudio(AppDomain.CurrentDomain.BaseDirectory);return app.Run(studio.window);}catch(Exception e){Forms.MessageBox.Show(e.Message,"Dragon Studio");return 1;}}}
}
