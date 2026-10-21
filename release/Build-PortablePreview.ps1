param([string]$ArchivePath,[string]$WorkDirectory,[string]$Version)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if(!$Version){$Version=(Get-Content (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()}
if($Version -notmatch '^\d+\.\d+\.\d+-preview(?:\.\d+)?$'){throw '预览版本号格式错误'}
if(!$WorkDirectory){$WorkDirectory=Join-Path ([IO.Path]::GetTempPath()) ('GameTimePackage-'+[Guid]::NewGuid().ToString('N'))}
if(Test-Path -LiteralPath $WorkDirectory){throw '打包目录必须为尚不存在的新目录'}
New-Item -ItemType Directory $WorkDirectory -Force | Out-Null
if(!$ArchivePath){
 $ArchivePath=Join-Path $WorkDirectory 'Playnite-10.63.7z'
 Invoke-WebRequest 'https://github.com/JosefNemec/Playnite/releases/download/10.63/10.63.7z' -OutFile $ArchivePath
}
if((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne '9AF9A0DB330C97879697BEAC9F819C16F9F544E712261A83FA4E62A8F9A2C787'){throw 'Playnite 官方包校验失败'}
$payload=Join-Path $WorkDirectory 'GameTime'
$app=Join-Path $payload 'Playnite'
New-Item -ItemType Directory $app -Force | Out-Null
$sevenZip=Join-Path ${env:ProgramFiles} '7-Zip\7z.exe'
if(Test-Path $sevenZip){& $sevenZip x $ArchivePath "-o$app" -y | Out-Null}else{& tar -xf $ArchivePath -C $app}
if($LASTEXITCODE -ne 0){throw '官方运行时解压失败'}
$source=Join-Path $payload '源码'
New-Item -ItemType Directory $source -Force | Out-Null
foreach($name in @('Build-Theme.ps1','GameTimeLibrary.psm1','Main.xaml','ListGameItemTemplate.xaml')){Copy-Item (Join-Path $repo "源码\$name") $source}
New-Item -ItemType Directory (Join-Path $payload 'assets') -Force | Out-Null
Copy-Item (Join-Path $repo 'assets\paper-room.png') (Join-Path $payload 'assets')
& (Join-Path $source 'Build-Theme.ps1') -DesktopPreview
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$wpf=Join-Path $framework 'WPF'
$bridge=Join-Path $app 'Extensions\GameTimeLibrary\GameTime.RemoteBridge.dll'
& (Join-Path $framework 'csc.exe') /nologo /codepage:65001 /target:library "/out:$bridge" "/reference:$app\Playnite.SDK.dll" /reference:System.Web.Extensions.dll /reference:System.Xaml.dll "/reference:$wpf\PresentationFramework.dll" "/reference:$wpf\PresentationCore.dll" "/reference:$wpf\WindowsBase.dll" (Join-Path $repo '源码\RemoteBridge.cs') (Join-Path $repo '源码\MultiClientState.cs')
if($LASTEXITCODE -ne 0){throw '全屏扩展编译失败'}
Copy-Item (Join-Path $repo 'downloads\GameTime.exe') (Join-Path $payload 'GameTime.exe')
Copy-Item (Join-Path $PSScriptRoot 'Launcher.Baseline.cs') $source
@'
游戏时光 · 游戏大厅预览版

完整解压本文件夹，打开 GameTime.exe。请保留旁边的 Playnite 文件夹。
默认扫描 G:\APP；没有该目录时，可打开 Playnite\Playnite.DesktopApp.exe 手动添加游戏。
本版为中文手绘游戏大厅预览版，手机扫码遥控尚未发布，因此没有二维码入口。
手柄使用十字键或左摇杆选择、A 开始、B 返回；键盘使用方向键和 Enter。
启动器与游戏操作是不同层次，实体 Xbox 手柄和实际游戏游玩仍需要本机验收。
基础启动器源码保留在源码\Launcher.Baseline.cs，完整项目说明见公开仓库。
项目：https://github.com/ID-LiuDaZhi/gametime-launcher
第三方许可请保留 Playnite\license.txt。
'@ | Set-Content (Join-Path $payload 'README.txt') -Encoding utf8BOM
@{version=$Version;phoneRemoteEnabled=$false;runtime='Playnite 10.63';launcher='verified-baseline';sourceCommit=$env:GITHUB_SHA;createdUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $payload 'release-info.json') -Encoding UTF8
& (Join-Path $PSScriptRoot 'Test-PortablePreview.ps1') -Directory $payload
$out=Join-Path $WorkDirectory 'output'
New-Item -ItemType Directory $out -Force | Out-Null
$zip=Join-Path $out "GameTime-Windows-v$Version.zip"
if(Test-Path $sevenZip){& $sevenZip a -tzip -mx=5 $zip (Join-Path $WorkDirectory 'GameTime') | Out-Null}else{Compress-Archive -LiteralPath $payload -DestinationPath $zip -CompressionLevel Optimal}
if($LASTEXITCODE -ne 0){throw 'ZIP 打包失败'}
Copy-Item (Join-Path $payload 'GameTime.exe') $out
$hashes=foreach($file in @($zip,(Join-Path $out 'GameTime.exe'))){'{0}  {1}' -f (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path $file -Leaf)}
$hashes | Set-Content (Join-Path $out 'SHA256SUMS.txt') -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try{if(!($archive.Entries | Where-Object FullName -EQ 'GameTime/GameTime.exe')){throw '压缩包缺少根启动器'}}finally{$archive.Dispose()}
if($env:GITHUB_OUTPUT){"artifact_dir=$out" | Out-File $env:GITHUB_OUTPUT -Append -Encoding UTF8}
Write-Output "Portable package: $out"
