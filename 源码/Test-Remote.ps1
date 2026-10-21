param([int]$Port=28771)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sessionFile=Join-Path $root '手机遥控\session.json'
if(!(Test-Path $sessionFile)){throw 'FAIL: 手机遥控服务尚未创建本次连接信息'}
$session=Get-Content $sessionFile -Raw | ConvertFrom-Json
$base="http://127.0.0.1:$($session.port)"
$headers=@{'X-GameTime-Key'=$session.key;'X-GameTime-Client'='11111111111111111111111111111111'}
function StatusCode($url,$method='GET',$requestHeaders=@{},$body=$null){
 $params=@{Uri=$url;Method=$method;Headers=$requestHeaders;SkipHttpErrorCheck=$true}
 if($null -ne $body){$params.Body=$body;$params.ContentType='application/json'}
 (Invoke-WebRequest @params).StatusCode
}
if((StatusCode "$base/api/state") -ne 403){throw 'FAIL: 无凭证请求未被拒绝'}
if((StatusCode "$base/api/state" 'GET' @{'X-GameTime-Key'='incorrect'}) -ne 403){throw 'FAIL: 错误凭证请求未被拒绝'}
$state=Invoke-RestMethod "$base/api/state" -Headers $headers
if(!$state.games -or $state.games.Count -lt 2){throw 'FAIL: 手机游戏列表没有同步'}
if((StatusCode "$base/api/action" 'POST' $headers '{"action":"run-shell"}') -ne 400){throw 'FAIL: 未知操作未被拒绝'}
if((StatusCode "$base/api/action" 'POST' $headers '{"action":"select","gameId":"../../bad"}') -ne 400){throw 'FAIL: 无效游戏编号未被拒绝'}
$foreign=@{'X-GameTime-Key'=$session.key;Origin='http://example.invalid'}
if((StatusCode "$base/api/action" 'POST' $foreign '{"action":"next"}') -ne 403){throw 'FAIL: 跨站操作未被拒绝'}
$before=$state.selectedId
$result=Invoke-RestMethod "$base/api/action" -Method POST -Headers $headers -ContentType 'application/json' -Body '{"action":"next"}'
$after=$null
for($i=0;$i -lt 25;$i++){Start-Sleep -Milliseconds 200;$after=Invoke-RestMethod "$base/api/state" -Headers $headers;if($after.lastCommand.id -eq $result.requestId){break}}
if(!$after.lastCommand.ok -or $after.selectedId -eq $before){throw 'FAIL: 下一款指令未在电脑端执行'}
$null=Invoke-RestMethod "$base/api/action" -Method POST -Headers $headers -ContentType 'application/json' -Body '{"action":"previous"}'
'PASS: 连接凭证、跨站拒绝、操作白名单、游戏列表同步、下一款指令与电脑回执'
