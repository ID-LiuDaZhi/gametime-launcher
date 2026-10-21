$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$file=Join-Path $root '手机遥控\session.json'
if(!(Test-Path $file)){throw '手机服务尚未启动，不能执行多手机集成测试'}
$session=Get-Content $file -Raw | ConvertFrom-Json
$base="http://127.0.0.1:$($session.port)"
$a=@{'X-GameTime-Key'=$session.key;'X-GameTime-Client'='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'}
$b=@{'X-GameTime-Key'=$session.key;'X-GameTime-Client'='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'}
$initial=Invoke-RestMethod "$base/api/state" -Headers $a
if($initial.games.Count -lt 2){throw '至少需要两个游戏进行选择联调'}
$null=Invoke-RestMethod "$base/api/state" -Headers $b
function Send-Selection($headers,$id){Invoke-RestMethod "$base/api/action" -Method POST -Headers $headers -ContentType 'application/json' -Body (@{action='select';gameId=$id}|ConvertTo-Json -Compress)}
try{
 $one=Send-Selection $a $initial.games[0].id
 $two=Send-Selection $b $initial.games[1].id
 for($i=0;$i -lt 25;$i++){
  Start-Sleep -Milliseconds 200
  $sa=Invoke-RestMethod "$base/api/state" -Headers $a
  $sb=Invoke-RestMethod "$base/api/state" -Headers $b
  $ackA=@($sa.receipts | Where-Object id -EQ $one.requestId)
  $ackB=@($sb.receipts | Where-Object id -EQ $two.requestId)
  if($ackA.Count -and $ackB.Count){break}
 }
 if(!$ackA.Count -or !$ackB.Count -or !$ackA[0].ok -or !$ackB[0].ok){throw '两个控制端未分别收到执行回执'}
 if($sa.connectedClients -lt 2 -or $sb.connectedClients -lt 2){throw '在线控制端数量未同步'}
 if(@($sa.receipts | Where-Object clientId -NE $a['X-GameTime-Client']).Count){throw 'A 收到了其他手机的回执'}
 if(@($sb.receipts | Where-Object clientId -NE $b['X-GameTime-Client']).Count){throw 'B 收到了其他手机的回执'}
 if($sa.selectedId -ne $initial.games[1].id -or $sb.selectedId -ne $initial.games[1].id){throw '多端当前选择不同步或指令顺序错误'}
 'PASS: 两个模拟控制端同时在线、交错选游戏、独立回执和共享选择状态'
}finally{if($initial.selectedId){$null=Send-Selection $a $initial.selectedId}}
