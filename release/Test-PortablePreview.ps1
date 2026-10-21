param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference='Stop'
$required=@('GameTime.exe','Playnite\Playnite.FullscreenApp.exe','Playnite\Playnite.SDK.dll','Playnite\license.txt','Playnite\config.json','Playnite\fullscreenConfig.json','Playnite\Themes\Fullscreen\GameTime\Views\Main.xaml','Playnite\Themes\Fullscreen\GameTime\Images\paper-room.png','Playnite\Extensions\GameTimeLibrary\GameTimeLibrary.psm1','Playnite\Extensions\GameTimeLibrary\GameTime.RemoteBridge.dll','README.txt','release-info.json')
foreach($relative in $required){if(!(Test-Path -LiteralPath (Join-Path $Directory $relative) -PathType Leaf)){throw "便携包缺少文件：$relative"}}
$exe=Join-Path $Directory 'GameTime.exe'
if((Get-FileHash $exe -Algorithm SHA256).Hash -ne '08EF8D8A0C322A2CC48A7486348D6D14668AE7FE153E8B0EFAAF9889AA6069E4'){throw '基础启动器校验失败'}
$bytes=[IO.File]::ReadAllBytes($exe)
if($bytes[0] -ne 77 -or $bytes[1] -ne 90){throw '启动器不是 Windows EXE'}
$config=Get-Content (Join-Path $Directory 'Playnite\config.json') -Raw | ConvertFrom-Json
if($config.DatabasePath -ne 'library' -or !$config.StartInFullscreen -or $config.Language -ne 'zh_CN'){throw '便携版配置错误'}
$main=Get-Content (Join-Path $Directory 'Playnite\Themes\Fullscreen\GameTime\Views\Main.xaml') -Raw
$null=[xml]$main
if($main -match 'GameTime_QrImage|GameTime_RemoteButton'){throw '预览版不应显示未启用的扫码入口'}
$info=Get-Content (Join-Path $Directory 'release-info.json') -Raw | ConvertFrom-Json
if($info.phoneRemoteEnabled){throw '预览版不得启用手机服务'}
$officialCatalogRoot=[IO.Path]::GetFullPath((Join-Path $Directory 'Playnite\Emulation\Database'))+[IO.Path]::DirectorySeparatorChar
$forbidden=Get-ChildItem -LiteralPath $Directory -Recurse -File | Where-Object {
 $_.Name -match '^(session|state|clients)\.json$|^server\.alive$|^qr\.png$|\.log$' -or
 ($_.Extension -eq '.db' -and !$_.FullName.StartsWith($officialCatalogRoot,[StringComparison]::OrdinalIgnoreCase))
}
if($forbidden){throw ('便携包混入了运行数据：'+($forbidden.Name -join ', '))}
'PASS: 便携文件完整、EXE 校验、中文全屏配置、扫码入口禁用、无个人运行数据'
