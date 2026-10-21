$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$framework='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF'
$app=Join-Path $root 'Playnite'
$out=Join-Path $PSScriptRoot '构建'
New-Item -ItemType Directory $out -Force | Out-Null
if(Get-Process -Name '游戏时光','Playnite.FullscreenApp' -ErrorAction SilentlyContinue){throw '请先关闭当前游戏大厅和手机遥控，再构建。'}
if(!(Test-Path (Join-Path $app 'Playnite.SDK.dll')) -or !(Test-Path (Join-Path $PSScriptRoot 'lib\QRCoder.dll'))){throw '缺少依赖，请先运行源码\Setup-Dependencies.ps1。'}
& $csc /nologo /codepage:65001 /target:library "/out:$out\GameTime.RemoteBridge.dll" "/reference:$app\Playnite.SDK.dll" /reference:System.Web.Extensions.dll /reference:System.Xaml.dll "/reference:$framework\PresentationFramework.dll" "/reference:$framework\PresentationCore.dll" "/reference:$framework\WindowsBase.dll" (Join-Path $PSScriptRoot 'RemoteBridge.cs') (Join-Path $PSScriptRoot 'MultiClientState.cs')
if($LASTEXITCODE -ne 0){throw 'Bridge build failed'}
$qr=Join-Path $PSScriptRoot 'lib\QRCoder.dll'
& $csc /nologo /codepage:65001 /target:winexe "/out:$out\游戏时光.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/reference:$qr" "/resource:$PSScriptRoot\remote.html,GameTime.remote.html" (Join-Path $PSScriptRoot 'Launcher.cs') (Join-Path $PSScriptRoot 'RemoteServer.cs') (Join-Path $PSScriptRoot 'MultiClientState.cs')
if($LASTEXITCODE -ne 0){throw 'App build failed'}
'Build passed'
& (Join-Path $PSScriptRoot 'Build-Theme.ps1')
Copy-Item (Join-Path $out 'GameTime.RemoteBridge.dll') (Join-Path $app 'Extensions\GameTimeLibrary') -Force
Copy-Item (Join-Path $out '游戏时光.exe') $root -Force
Copy-Item $qr $root -Force
'Deployment passed'

