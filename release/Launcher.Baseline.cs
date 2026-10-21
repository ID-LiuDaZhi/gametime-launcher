using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
internal static class Launcher {
 [STAThread] private static void Main() {
  string app=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Playnite","Playnite.FullscreenApp.exe");
  if(!File.Exists(app)){MessageBox.Show("找不到 Playnite 文件夹，请将游戏时光.exe 与 Playnite 文件夹放在一起。","游戏时光");return;}
  try { Process.Start(new ProcessStartInfo(app){WorkingDirectory=Path.GetDirectoryName(app),UseShellExecute=false,WindowStyle=ProcessWindowStyle.Normal}); }
  catch(Exception e){MessageBox.Show("无法打开游戏大厅："+e.Message,"游戏时光");}
 }
}
