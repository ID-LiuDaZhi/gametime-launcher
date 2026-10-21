using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Playnite.SDK;

namespace GameTime {
 public sealed class RemoteBridge : IDisposable {
  readonly IPlayniteAPI api;
  readonly string folder;
  readonly DispatcherTimer timer=new DispatcherTimer();
  readonly JavaScriptSerializer json=new JavaScriptSerializer();
  bool fullscreen=true;
  bool ticking;
  string lastId="",lastMessage="";bool lastOk=true;
  readonly RemoteReceipts receipts=new RemoteReceipts();
  DateTime launchPendingUntil=DateTime.MinValue;
  readonly HashSet<Button> hooked=new HashSet<Button>();
  public RemoteBridge(IPlayniteAPI api,string root){this.api=api;folder=Path.Combine(root,"手机遥控");Directory.CreateDirectory(folder);Directory.CreateDirectory(Path.Combine(folder,"queue"));timer.Interval=TimeSpan.FromMilliseconds(220);timer.Tick+=Tick;timer.Start();Tick(null,EventArgs.Empty);}
  Window MainWindow(){return Application.Current.Windows.Cast<Window>().FirstOrDefault(w=>w.GetType().FullName=="Playnite.FullscreenApp.Windows.MainWindow")??Application.Current.MainWindow;}
  IEnumerable<FrameworkElement> Elements(DependencyObject parent){if(parent==null)yield break;var element=parent as FrameworkElement;if(element!=null)yield return element;for(int i=0;i<VisualTreeHelper.GetChildrenCount(parent);i++)foreach(var child in Elements(VisualTreeHelper.GetChild(parent,i)))yield return child;}
  public void EnterFullscreen(){
   var w=MainWindow();if(w==null)throw new InvalidOperationException("大厅窗口尚未就绪");
   w.WindowStyle=WindowStyle.None;w.ResizeMode=ResizeMode.NoResize;w.WindowState=WindowState.Maximized;w.Show();w.Activate();fullscreen=true;
  }
  void HookControls(){
   var w=MainWindow();if(w==null||!w.IsVisible)return;
   // Walk once after templates are loaded; new templates get their own handlers.
   foreach(var element in Elements(w)){
    var button=element as Button;
    if(button!=null&&(button.Name=="GameTime_FullscreenButton"||button.Name=="GameTime_RemoteButton")&&!hooked.Contains(button)){
     hooked.Add(button);
     if(button.Name=="GameTime_FullscreenButton")button.Click+=delegate{try{EnterFullscreen();}catch(Exception e){lastMessage=e.Message;}};
     else button.Click+=delegate{if(Session()==null){api.Dialogs.ShowMessage("手机遥控连接服务尚未启动。本次新版 EXE 在部署时被 Windows 拦截，扫码功能尚不可用。","手机遥控尚未启用");return;}File.WriteAllText(Path.Combine(folder,"show-qr"),"show");};
    }
   }
  }
  void UpdateQr(Dictionary<string,object> session){
   var window=MainWindow();if(window==null)return;
   string qr=Path.Combine(folder,"qr.png");string signature=File.Exists(qr)?File.GetLastWriteTimeUtc(qr).Ticks.ToString():"";
   foreach(var element in Elements(window)){
    if(element.Name=="GameTime_FullscreenButton"){((Button)element).Content="全屏";}
    if(element.Name=="GameTime_RemoteAddress")((TextBlock)element).Text=session==null?"手机遥控尚未启用":Convert.ToString(session["address"])+":"+Convert.ToString(session["port"]);
    var image=element as Image;
    if(image!=null&&image.Name=="GameTime_QrImage"&&signature!=""&&image.Tag as string!=signature){
     using(var stream=File.OpenRead(qr)){var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.StreamSource=stream;bitmap.EndInit();bitmap.Freeze();image.Source=bitmap;}image.Tag=signature;
    }
   }
  }
  Dictionary<string,object> Session(){string path=Path.Combine(folder,"session.json");string pulse=Path.Combine(folder,"server.alive");if(!File.Exists(path)||!File.Exists(pulse)||(DateTime.UtcNow-File.GetLastWriteTimeUtc(pulse)).TotalSeconds>6)return null;return json.Deserialize<Dictionary<string,object>>(File.ReadAllText(path));}
  void Apply(Dictionary<string,object> command){
   string action=Convert.ToString(command["action"]);
   var games=api.MainView.FilteredGames.Where(g=>g.IsInstalled).ToList();
   var selected=api.MainView.SelectedGames.FirstOrDefault();
   if(action=="fullscreen"){EnterFullscreen();lastMessage="电脑已进入全屏";return;}
   if(action=="back"){api.MainView.SwitchToLibraryView();var window=MainWindow();if(window!=null){window.Show();window.Activate();}lastMessage="已返回游戏大厅";return;}
   if(games.Count==0)throw new InvalidOperationException("没有可启动的游戏");
   if(action=="next"||action=="previous"){
    int index=selected==null?-1:games.FindIndex(g=>g.Id==selected.Id);index=action=="next"?(index+1)%games.Count:(index<=0?games.Count-1:index-1);api.MainView.SwitchToLibraryView();api.MainView.SelectGame(games[index].Id);lastMessage="已选择："+games[index].Name;return;
   }
   if(action=="select"){
    Guid id;if(!Guid.TryParse(Convert.ToString(command["gameId"]),out id))throw new InvalidOperationException("游戏编号无效");var game=games.FirstOrDefault(g=>g.Id==id);if(game==null)throw new InvalidOperationException("游戏已不在当前列表");api.MainView.SwitchToLibraryView();api.MainView.SelectGame(id);lastMessage="已选择："+game.Name;return;
   }
   if(action=="play"){
    if(selected==null||!games.Any(g=>g.Id==selected.Id))throw new InvalidOperationException("请先选择游戏");
    if(api.Database.Games.Any(g=>g.IsRunning)||DateTime.UtcNow<launchPendingUntil)throw new InvalidOperationException("已有游戏正在运行或启动，请先在电脑上确认");
    launchPendingUntil=DateTime.UtcNow.AddSeconds(15);
    try{api.StartGame(selected.Id);}catch{launchPendingUntil=DateTime.MinValue;throw;}
    lastMessage="已发送启动请求："+selected.Name;return;
   }
   throw new InvalidOperationException("不支持此操作");
  }
  void Tick(object sender,EventArgs args){
   if(ticking)return;ticking=true;
   try{
    HookControls();var session=Session();UpdateQr(session);
    foreach(string file in Directory.GetFiles(Path.Combine(folder,"queue"),"*.json").OrderBy(x=>x).Take(8)){
     string client="",request="";bool valid=false;
     try{
      var command=json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file));
      if(session==null||Convert.ToString(command["session"])!=Convert.ToString(session["key"]))continue;
      client=Convert.ToString(command["clientId"]);request=Convert.ToString(command["id"]);
      if(!RemoteClients.Valid(client))continue;
      valid=true;lastId=request;lastOk=true;
      if((DateTime.UtcNow-DateTime.Parse(Convert.ToString(command["created"]),null,System.Globalization.DateTimeStyles.RoundtripKind)).TotalSeconds>6)throw new InvalidOperationException("操作等待过久，已取消，请重试");
      Apply(command);
     }catch(Exception error){lastOk=false;lastMessage=error.Message;}
     finally{if(valid)receipts.Record(request,client,lastOk,lastMessage,DateTime.UtcNow);try{File.Delete(file);}catch{}}
    }
    var selected=api.MainView.SelectedGames.FirstOrDefault();var running=api.Database.Games.FirstOrDefault(g=>g.IsRunning);
    string text=json.Serialize(new{games=api.MainView.FilteredGames.Where(g=>g.IsInstalled).Select(g=>new{id=g.Id.ToString(),name=g.Name}).ToArray(),selectedId=selected==null?"":selected.Id.ToString(),selectedName=selected==null?"":selected.Name,runningName=running==null?"":running.Name,fullscreen=fullscreen,updated=DateTime.UtcNow.ToString("o"),receipts=receipts.Snapshot(DateTime.UtcNow),lastCommand=new{id=lastId,ok=lastOk,message=lastMessage}});
    string path=Path.Combine(folder,"state.json"),temp=path+".tmp";File.WriteAllText(temp,text,new UTF8Encoding(false));if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);
   }catch(Exception e){try{File.WriteAllText(Path.Combine(folder,"bridge-error.txt"),DateTime.UtcNow.ToString("o")+" "+e.ToString());}catch{}}
   finally{ticking=false;}
  }
  public void Dispose(){timer.Stop();hooked.Clear();}
 }
}
