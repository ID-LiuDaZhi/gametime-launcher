using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using QRCoder;

namespace GameTime {
 public sealed class RemoteServer : IDisposable {
  public readonly string Root, Folder, Key;
  public int Port {get;private set;}
  public List<string> Addresses {get;private set;}
  public string Preferred {get;private set;}
  readonly List<TcpListener> listeners=new List<TcpListener>();
  readonly Semaphore slots=new Semaphore(16,16);
  readonly RemoteClients clients=new RemoteClients();
  readonly RemoteCommandOrder order=new RemoteCommandOrder();
  readonly object queueGate=new object();
  volatile bool stopping;
  public RemoteServer(string root) {
   Root=root; Folder=Path.Combine(root,"手机遥控");Directory.CreateDirectory(Folder);Directory.CreateDirectory(Path.Combine(Folder,"queue"));
   byte[] random=new byte[24];using(var rng=RandomNumberGenerator.Create())rng.GetBytes(random);Key=BitConverter.ToString(random).Replace("-","").ToLowerInvariant();
   Addresses=GetAddresses();
   for(int p=28771;p<28781;p++){
    try{
     foreach(string ip in Addresses.Concat(new[]{"127.0.0.1"})){var l=new TcpListener(IPAddress.Parse(ip),p);l.Start(16);listeners.Add(l);}
     Port=p;break;
    }catch(SocketException){foreach(var l in listeners)l.Stop();listeners.Clear();}
   }
   if(Port==0)throw new IOException("28771–28780 端口均不可用，请关闭重复的游戏时光后重试。");
   SetAddress(Addresses.FirstOrDefault()??"127.0.0.1");
   foreach(var listener in listeners){var captured=listener;ThreadPool.QueueUserWorkItem(delegate{Accept(captured);});}
  }
  public static List<string> GetAddresses(){
   var found=new List<Tuple<string,bool>>();
   foreach(var nic in NetworkInterface.GetAllNetworkInterfaces()){
    if(nic.OperationalStatus!=OperationalStatus.Up || nic.NetworkInterfaceType==NetworkInterfaceType.Loopback || nic.NetworkInterfaceType==NetworkInterfaceType.Tunnel)continue;
    var props=nic.GetIPProperties();bool gateway=props.GatewayAddresses.Any(g=>g.Address.AddressFamily==AddressFamily.InterNetwork&&!g.Address.Equals(IPAddress.Any));
    foreach(var a in props.UnicastAddresses){if(a.Address.AddressFamily!=AddressFamily.InterNetwork)continue;byte[] b=a.Address.GetAddressBytes();if(b[0]==10||(b[0]==172&&b[1]>=16&&b[1]<=31)||(b[0]==192&&b[1]==168))found.Add(Tuple.Create(a.Address.ToString(),gateway));}
   }
   return found.OrderByDescending(x=>x.Item2).Select(x=>x.Item1).Distinct().ToList();
  }
  public string Url(string ip){return "http://"+ip+":"+Port+"/#code="+Key;}
  public void SetAddress(string ip){
   if(ip!="127.0.0.1"&&!Addresses.Contains(ip))throw new ArgumentException("未知网卡");Preferred=ip;
   using(var generator=new QRCodeGenerator())using(var data=generator.CreateQrCode(Url(ip),QRCodeGenerator.ECCLevel.M))using(var qr=new QRCode(data))using(var bitmap=qr.GetGraphic(6)){
    string tmp=Path.Combine(Folder,"qr.tmp.png");bitmap.Save(tmp,ImageFormat.Png);ReplaceFile(tmp,Path.Combine(Folder,"qr.png"));
   }
   WriteJson(Path.Combine(Folder,"session.json"),new{key=Key,port=Port,address=ip,addresses=Addresses,updated=DateTime.UtcNow.ToString("o")});
  }
  public static void ReplaceFile(string temp,string target){if(File.Exists(target))File.Replace(temp,target,null);else File.Move(temp,target);}
  public static void WriteJson(string path,object value){string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";File.WriteAllText(temp,new JavaScriptSerializer().Serialize(value),new UTF8Encoding(false));ReplaceFile(temp,path);}
  static bool EqualKey(string a,string b){if(a==null||a.Length!=b.Length)return false;int n=0;for(int i=0;i<b.Length;i++)n|=a[i]^b[i];return n==0;}
  void Accept(TcpListener listener){while(!stopping){try{var c=listener.AcceptTcpClient();if(!slots.WaitOne(0)){c.Close();continue;}ThreadPool.QueueUserWorkItem(delegate{try{Handle(c);}catch{}finally{c.Close();slots.Release();}});}catch{if(stopping)return;}}}
  void Reply(NetworkStream stream,int status,string body,string type){byte[] bytes=Encoding.UTF8.GetBytes(body);string head="HTTP/1.1 "+status+" "+(status==200?"OK":status==202?"Accepted":"Error")+"\r\nContent-Type: "+type+"; charset=utf-8\r\nContent-Length: "+bytes.Length+"\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n";byte[] h=Encoding.ASCII.GetBytes(head);stream.Write(h,0,h.Length);stream.Write(bytes,0,bytes.Length);}
  void Handle(TcpClient client){
   client.ReceiveTimeout=3000;client.SendTimeout=3000;
   using(var s=client.GetStream()){
    var bytes=new List<byte>();int ch;
    while((ch=s.ReadByte())>=0){bytes.Add((byte)ch);int n=bytes.Count;if(n>8192){Reply(s,413,"请求过大","text/plain");return;}if(n>=4&&bytes[n-4]==13&&bytes[n-3]==10&&bytes[n-2]==13&&bytes[n-1]==10)break;}
    string[] lines=Encoding.ASCII.GetString(bytes.ToArray()).Split(new[]{"\r\n"},StringSplitOptions.None);string[] first=lines[0].Split(' ');
    if(first.Length!=3){Reply(s,400,"请求无效","text/plain");return;}
    var headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
    foreach(string line in lines.Skip(1)){int i=line.IndexOf(':');if(i>0){string k=line.Substring(0,i).Trim();if(headers.ContainsKey(k)){Reply(s,400,"重复请求头","text/plain");return;}headers[k]=line.Substring(i+1).Trim();}}
    string host;headers.TryGetValue("Host",out host);
    if(!Addresses.Concat(new[]{"127.0.0.1","localhost"}).Any(a=>host==a+":"+Port)){Reply(s,403,"地址无效","text/plain");return;}
    string origin;if(headers.TryGetValue("Origin",out origin)&&origin!="http://"+host){Reply(s,403,"请从二维码页面操作","text/plain");return;}
    if(first[0]=="GET"&&first[1]=="/"){
     using(var resource=typeof(RemoteServer).Assembly.GetManifestResourceStream("GameTime.remote.html"))using(var reader=new StreamReader(resource))Reply(s,200,reader.ReadToEnd(),"text/html");return;
    }
    string key;headers.TryGetValue("X-GameTime-Key",out key);if(!EqualKey(key,Key)){Reply(s,403,"请重新扫描电脑上的二维码","text/plain");return;}
    string clientId;headers.TryGetValue("X-GameTime-Client",out clientId);
    if(!RemoteClients.Valid(clientId)){Reply(s,400,"控制端编号无效，请刷新页面","text/plain");return;}
    if(!clients.Touch(clientId,DateTime.UtcNow)){Reply(s,429,"连接较多，请稍后再试","text/plain");return;}
    string statePath=Path.Combine(Folder,"state.json");
    if(first[0]=="GET"&&first[1]=="/api/state"){
     if(!File.Exists(statePath)||(DateTime.UtcNow-File.GetLastWriteTimeUtc(statePath)).TotalSeconds>6){Reply(s,503,"大厅尚未就绪，请稍后","text/plain");return;}
     var serializer=new JavaScriptSerializer();
     var view=serializer.Deserialize<Dictionary<string,object>>(File.ReadAllText(statePath));
     RemoteStateView.FilterReceipts(view,clientId,clients.Count(DateTime.UtcNow));
     Reply(s,200,serializer.Serialize(view),"application/json");return;
    }
    if(first[0]!="POST"||first[1]!="/api/action"){Reply(s,404,"没有此操作","text/plain");return;}
    int length;string rawLength;headers.TryGetValue("Content-Length",out rawLength);
    if(headers.ContainsKey("Transfer-Encoding")||!Int32.TryParse(rawLength,out length)||length<1||length>512){Reply(s,400,"请求长度无效","text/plain");return;}
    byte[] body=new byte[length];for(int off=0;off<length;){int n=s.Read(body,off,length-off);if(n==0)return;off+=n;}
    Dictionary<string,object> command;
    try{command=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(body));}catch{Reply(s,400,"操作无效","text/plain");return;}
    object actionValue,idValue;string action=command.TryGetValue("action",out actionValue)?actionValue as string:null;string gameId=command.TryGetValue("gameId",out idValue)?idValue as string:null;
    if(!new[]{"next","previous","select","play","back","fullscreen"}.Contains(action)){Reply(s,400,"操作无效","text/plain");return;}
    Guid parsed;if(action=="select"&&(!Guid.TryParse(gameId,out parsed)||parsed==Guid.Empty)){Reply(s,400,"游戏编号无效","text/plain");return;}
    if(!File.Exists(statePath)||(DateTime.UtcNow-File.GetLastWriteTimeUtc(statePath)).TotalSeconds>6){Reply(s,503,"大厅尚未就绪","text/plain");return;}
    string requestId=Guid.NewGuid().ToString("N");
    lock(queueGate){
     string queue=Path.Combine(Folder,"queue");if(Directory.GetFiles(queue,"*.json").Length>=48){Reply(s,429,"操作太快，请稍等","text/plain");return;}
     WriteJson(Path.Combine(queue,order.Next(DateTime.UtcNow.Ticks).ToString("D20")+"-"+requestId+".json"),new{id=requestId,clientId=clientId,session=Key,action=action,gameId=gameId,created=DateTime.UtcNow.ToString("o")});
    }
    Reply(s,202,new JavaScriptSerializer().Serialize(new{requestId=requestId}),"application/json");
   }
  }
  public void Dispose(){stopping=true;foreach(var l in listeners)l.Stop();}
 }

 public sealed class RemoteContext : ApplicationContext {
  readonly RemoteServer server;
  readonly NotifyIcon tray;
  readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
  Form form;PictureBox picture;ComboBox network;Label address;
  DateTime start=DateTime.UtcNow;DateTime? absent;
  public RemoteContext(RemoteServer value){
   server=value;tray=new NotifyIcon{Icon=SystemIcons.Application,Text="游戏时光 · 手机遥控",Visible=true};
   var menu=new ContextMenuStrip();menu.Items.Add("显示手机连接二维码",null,delegate{ShowQr();});menu.Items.Add("停止手机遥控",null,delegate{ExitThread();});tray.ContextMenuStrip=menu;tray.DoubleClick+=delegate{ShowQr();};
   timer.Interval=800;timer.Tick+=Tick;timer.Start();
  }
  void Tick(object sender,EventArgs args){
   try{File.WriteAllText(Path.Combine(server.Folder,"server.alive"),"alive");}catch{}
   string show=Path.Combine(server.Folder,"show-qr");if(File.Exists(show)){try{File.Delete(show);}catch{}ShowQr();}
   if((DateTime.UtcNow-start).TotalSeconds<15)return;
   bool running=Process.GetProcessesByName("Playnite.FullscreenApp").Any(p=>{try{return String.Equals(Path.GetFullPath(p.MainModule.FileName),Path.Combine(server.Root,"Playnite","Playnite.FullscreenApp.exe"),StringComparison.OrdinalIgnoreCase);}catch{return false;}});
   if(running)absent=null;else if(absent==null)absent=DateTime.UtcNow;else if((DateTime.UtcNow-absent.Value).TotalSeconds>4)ExitThread();
  }
  public void ShowQr(){
   if(form==null||form.IsDisposed){
    form=new Form{Text="游戏时光 · 手机扫码遥控",ClientSize=new Size(440,590),StartPosition=FormStartPosition.CenterScreen,BackColor=Color.FromArgb(247,240,226),Font=new Font("Microsoft YaHei UI",11),FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false};
    var title=new Label{Text="手机与电脑连接同一局域网",AutoSize=false,TextAlign=ContentAlignment.MiddleCenter,Bounds=new Rectangle(15,15,410,45)};
    picture=new PictureBox{Bounds=new Rectangle(65,70,310,310),SizeMode=PictureBoxSizeMode.Zoom,BackColor=Color.White};
    network=new ComboBox{Bounds=new Rectangle(35,400,370,32),DropDownStyle=ComboBoxStyle.DropDownList};network.Items.AddRange(server.Addresses.Cast<object>().ToArray());if(network.Items.Count==0)network.Items.Add("127.0.0.1");network.SelectedItem=server.Preferred;
    address=new Label{Bounds=new Rectangle(20,446,400,44),TextAlign=ContentAlignment.MiddleCenter};
    var hint=new Label{Bounds=new Rectangle(25,495,390,78),Text="用手机相机或微信扫码，用浏览器打开。\n连接不上时切换上面的网卡地址。\n二维码每次重开都会更新。",TextAlign=ContentAlignment.MiddleCenter,ForeColor=Color.DimGray};
    form.Controls.AddRange(new Control[]{title,picture,network,address,hint});
    network.SelectedIndexChanged+=delegate{server.SetAddress((string)network.SelectedItem);RefreshQr();};
   }
   RefreshQr();form.Show();form.WindowState=FormWindowState.Normal;form.Activate();
  }
  void RefreshQr(){using(var stream=File.OpenRead(Path.Combine(server.Folder,"qr.png"))){var old=picture.Image;picture.Image=new Bitmap(stream);if(old!=null)old.Dispose();}address.Text="http://"+server.Preferred+":"+server.Port;}
  protected override void ExitThreadCore(){timer.Stop();server.Dispose();tray.Visible=false;tray.Dispose();if(form!=null)form.Dispose();base.ExitThreadCore();}
 }
}
