$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$downloads=Join-Path $root '下载'
New-Item -ItemType Directory $downloads -Force | Out-Null
function Get-VerifiedArchive([string]$Url,[string]$Destination,[string]$Sha256){
 if(!(Test-Path -LiteralPath $Destination)){Invoke-WebRequest -Uri $Url -OutFile $Destination}
 $actual=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
 if($actual -ne $Sha256){throw "下载包校验失败，请核实来源和文件：$Destination"}
}
$app=Join-Path $root 'Playnite'
if(!(Test-Path (Join-Path $app 'Playnite.SDK.dll'))){
 $archive=Join-Path $downloads 'Playnite-10.63.7z'
 Get-VerifiedArchive 'https://github.com/JosefNemec/Playnite/releases/download/10.63/10.63.7z' $archive '9AF9A0DB330C97879697BEAC9F819C16F9F544E712261A83FA4E62A8F9A2C787'
 New-Item -ItemType Directory $app -Force | Out-Null
 & tar -xf $archive -C $app
 if($LASTEXITCODE -ne 0){throw 'Playnite 解压失败'}
}
$lib=Join-Path $PSScriptRoot 'lib'
if(!(Test-Path (Join-Path $lib 'QRCoder.dll'))){
 $archive=Join-Path $downloads 'QRCoder-1.6.0.zip'
 Get-VerifiedArchive 'https://api.nuget.org/v3-flatcontainer/qrcoder/1.6.0/qrcoder.1.6.0.nupkg' $archive 'D84BFFE9DECF1FA2B8755610407959F998209029C3B6B95A1B282CEB9983A36F'
 $unpacked=Join-Path $downloads 'QRCoder-1.6.0'
 Expand-Archive -LiteralPath $archive -DestinationPath $unpacked -Force
 New-Item -ItemType Directory $lib -Force | Out-Null
 Copy-Item (Join-Path $unpacked 'lib\net40\QRCoder.dll') $lib -Force
}
'依赖已就绪。此脚本仅下载和解压，未启动 Playnite 或手机遥控。'
