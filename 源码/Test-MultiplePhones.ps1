$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'MultiClientState.cs'
if(!(Test-Path $source)){throw 'FAIL: 缺少多手机独立回执和在线状态管理'}
Add-Type -Path $source
$now=[DateTime]::UtcNow
$a='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$b='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$clients=New-Object GameTime.RemoteClients
if(!$clients.Touch($a,$now) -or !$clients.Touch($b,$now)){throw '两部手机应能同时上线'}
if($clients.Count($now) -ne 2){throw '在线数量应为 2'}
$null=$clients.Touch($a,$now.AddSeconds(10))
if($clients.Count($now.AddSeconds(16)) -ne 1){throw '只有断连超过 15 秒的控制端应离线'}
if($clients.Touch('invalid/id',$now)){throw '无效控制端编号应被拒绝'}
$receipts=New-Object GameTime.RemoteReceipts
$receipts.Record('a1',$a,$true,'A 选择成功',$now)
$receipts.Record('b1',$b,$true,'B 选择成功',$now)
$receipts.Record('a2',$a,$false,'已有游戏运行',$now)
$forA=@($receipts.ForClient($a,$now))
$forB=@($receipts.ForClient($b,$now))
if($forA.Count -ne 2 -or $forB.Count -ne 1){throw '各手机的回执必须分别保留'}
if($forA[0].id -ne 'a1' -or $forB[0].id -ne 'b1'){throw '后续手机的回执不应覆盖前一部手机的回执'}
Add-Type -TypeDefinition @'
using System.Collections.Generic;
public static class MultiPhoneFixture {
 public static Dictionary<string,object> State(string a,string b) {
  return new Dictionary<string,object>{{"receipts",new object[]{new Dictionary<string,object>{{"id","a1"},{"clientId",a}},new Dictionary<string,object>{{"id","b1"},{"clientId",b}}}}};
 }
}
'@
$view=[MultiPhoneFixture]::State($a,$b)
[GameTime.RemoteStateView]::FilterReceipts($view,$a,2)
if($view['receipts'].Count -ne 1 -or $view['lastCommand']['id'] -ne 'a1' -or $view['connectedClients'] -ne 2){throw '手机端状态应只包含自己的回执和共享在线数量'}
if(@($receipts.ForClient($a,$now.AddMinutes(3))).Count -ne 0){throw '过期回执应清理'}
$order=New-Object GameTime.RemoteCommandOrder
$first=$order.Next(100)
$second=$order.Next(100)
$third=$order.Next(90)
if(!($first -lt $second -and $second -lt $third)){throw '同时或时钟回拨时仍应保持指令顺序'}
'PASS: 多控制端同时上线、超时离线、独立回执、交错操作不覆盖、只返回本端回执、回执过期、指令顺序'
