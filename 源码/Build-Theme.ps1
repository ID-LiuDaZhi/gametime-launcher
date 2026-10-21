$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'Playnite'
$theme = Join-Path $app 'Themes\Fullscreen\GameTime'
if (!(Test-Path $theme)) { Copy-Item (Join-Path $app 'Themes\Fullscreen\Default') $theme -Recurse }
$background=Join-Path $root 'assets\paper-room.png'
if(!(Test-Path $background)){throw '缺少 assets\paper-room.png 背景素材'}
Copy-Item $background (Join-Path $theme 'Images\paper-room.png') -Force
@'
Id: GameTime_Handpainted
Name: 游戏时光 · 3D手绘
Author: GameTime
Version: 1.0.0
Mode: Fullscreen
ThemeApiVersion: 2.0.0
'@ | Set-Content (Join-Path $theme 'theme.yaml') -Encoding UTF8
$constants = Get-Content (Join-Path $app 'Themes\Fullscreen\Default\Constants.xaml') -Raw
$palette = @{ '#FFEC6200'='#FF50763D'; '#FFFFAA00'='#FF88A563'; '#FF8D919D'='#FFB9AC91'; '#FF2B354D'='#FFF3E9D8'; '#FF121830'='#FFE5D8BF'; '#FFEBEBEB'='#FF302F25'; '#FF757575'='#FF746E5D'; '#FF091F51'='#FFF7F0E2'; '#FF0B1027'='#FFEDE0C8'; '#AA0B1027'='#DAEFE5D1'; '#FF000623'='#FFF2E8D5'; '#EE0B1027'='#FFF2E8D5'; '#00091F51'='#00F7F0E2' }
foreach ($key in $palette.Keys) { $constants = $constants.Replace($key,$palette[$key]) }
$constants = $constants.Replace('{DynamicResource FontTitilliumWebLight}','Microsoft YaHei UI')
$constants | Set-Content (Join-Path $theme 'Constants.xaml') -Encoding UTF8
$main = Get-Content (Join-Path $PSScriptRoot 'Main.xaml') -Raw
$main | Set-Content (Join-Path $theme 'Views\Main.xaml') -Encoding UTF8
Copy-Item (Join-Path $PSScriptRoot 'ListGameItemTemplate.xaml') (Join-Path $theme 'DerivedStyles\ListGameItemTemplate.xaml') -Force
$item = Get-Content (Join-Path $app 'Themes\Fullscreen\Default\DerivedStyles\ListGameItemStyle.xaml') -Raw
$item = $item.Replace('CornerRadius="3"','CornerRadius="22"').Replace('ShadowDepth="0" Opacity="1"','ShadowDepth="8" Opacity="0.45"').Replace('BlurRadius="20"','BlurRadius="16"')
$item | Set-Content (Join-Path $theme 'DerivedStyles\ListGameItemStyle.xaml') -Encoding UTF8
$bottom = Get-Content (Join-Path $app 'Themes\Fullscreen\Default\DerivedStyles\ButtonBottomMenu.xaml') -Raw
$bottom = $bottom.Replace('FontFamily="{DynamicResource FontTitilliumWeb}"','FontFamily="Microsoft YaHei UI" Foreground="{TemplateBinding Foreground}"')
$bottom | Set-Content (Join-Path $theme 'DerivedStyles\ButtonBottomMenu.xaml') -Encoding UTF8
$extension = Join-Path $app 'Extensions\GameTimeLibrary'
New-Item $extension -ItemType Directory -Force | Out-Null
$scriptText = Get-Content (Join-Path $PSScriptRoot 'GameTimeLibrary.psm1') -Raw -Encoding UTF8
[IO.File]::WriteAllText((Join-Path $extension 'GameTimeLibrary.psm1'), $scriptText, [Text.UTF8Encoding]::new($true))
@'
Id: GameTimeLibrary_aa639ada-b7db-4653-bdd2-53cb29e6ea41
Name: 游戏时光本地游戏库
Author: GameTime
Version: 1.0.0
Module: GameTimeLibrary.psm1
Type: Script
'@ | Set-Content (Join-Path $extension 'extension.yaml') -Encoding UTF8
$configPath=Join-Path $app 'config.json'
$config = if(Test-Path $configPath){Get-Content $configPath -Raw | ConvertFrom-Json}else{[pscustomobject]@{ DatabasePath='library'; FirstTimeWizardComplete=$true; FullscreenItemSpacing=50; CoverAspectRatio=@{Width=2;Height=3} }}
foreach($pair in @{Language='zh_CN';StartInFullscreen=$true}.GetEnumerator()){$config | Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value -Force}
$config | ConvertTo-Json -Depth 30 | Set-Content $configPath -Encoding UTF8
$fsPath=Join-Path $app 'fullscreenConfig.json'
$fs=if(Test-Path $fsPath){Get-Content $fsPath -Raw | ConvertFrom-Json}else{[pscustomobject]@{}}
foreach($pair in @{ Theme='GameTime_Handpainted'; Rows=1; Columns=2; HorizontalLayout=$true; ShowGameTitles=$true; ShowClock=$true; ShowBattery=$false; ShowBackgroundImage=$false; EnableGameControllerSupport=$true; SwapStartDetailsAction=$true; SmoothScrolling=$true; ShowBatteryPercentage=$false }.GetEnumerator()){$fs | Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value -Force}
$fs | ConvertTo-Json -Depth 30 | Set-Content $fsPath -Encoding UTF8
Write-Output "Theme built: $theme"
