using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using System.Threading;
using GameTime;
internal static class Launcher {
 [STAThread] private static void Main() {
  string root=AppDomain.CurrentDomain.BaseDirectory;
  string app=Path.Combine(root,"Playnite","Playnite.FullscreenApp.exe");
  if(!File.Exists(app)){MessageBox.Show("找不到 Playnite 文件夹，请将游戏时光.exe 与 Playnite 文件夹放在一起。","游戏时光");return;}
  bool created;
  using(var mutex=new Mutex(true,"Local\\GameTimeRemote_2b7526e4",out created)){
   if(!created){string dir=Path.Combine(root,"手机遥控");Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"show-qr"),"show");return;}
   try {
    Application.EnableVisualStyles();
    using(var server=new RemoteServer(root)){
     Process.Start(new ProcessStartInfo(app){WorkingDirectory=Path.GetDirectoryName(app),UseShellExecute=false,WindowStyle=ProcessWindowStyle.Normal});
     Application.Run(new RemoteContext(server));
    }
   }
  catch(Exception e){MessageBox.Show("无法打开游戏大厅："+e.Message,"游戏时光");}
  }
 }
}
