$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'GameTimeLibrary.psm1') -Force
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('GameTime-Test-'+[Guid]::NewGuid())
function Put-Executable([string]$path) {
    $full=Join-Path $fixture $path
    New-Item (Split-Path $full) -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllBytes($full,[byte[]]@(0))
}
Put-Executable 'It.Takes.Two\Nuts\Binaries\Win64\ItTakesTwo.exe'
Put-Executable 'It.Takes.Two\Nuts\Binaries\Win64\ItTakesTwo_Trial.exe'
Put-Executable 'It.Takes.Two\Engine\CrashReportClient.exe'
Put-Executable 'Solo\Solo.exe'
Put-Executable 'Solo\unins000.exe'
Put-Executable 'Ambiguous\one.exe'
Put-Executable 'Ambiguous\two.exe'
$entries=@(Find-GameTimeEntries -Root $fixture)
if($entries.Count -ne 2){throw "Expected two unambiguous games, got $($entries.Count)"}
if(@($entries | Where-Object Path -Match 'Trial|unins|Crash|Ambiguous').Count){throw 'Imported excluded executable'}
if(!($entries | Where-Object Name -EQ '双人成行')){throw 'Chinese display name missing'}
if(@(Find-GameTimeEntries -Root (Join-Path $fixture 'Missing')).Count){throw 'Missing directory must be empty'}
foreach($entry in $entries){if((Split-Path $entry.Path) -ne $entry.WorkingDir){throw 'Working directory mismatch'}}
'PASS: trial exclusion, helper exclusion, ambiguous folder exclusion, Chinese title, missing drive, working directory'
# Only remove this test's newly created directory, after checking its absolute location.
$resolved=[IO.Path]::GetFullPath($fixture)
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if(!$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'GameTime-Test-*'){throw 'Unexpected fixture path'}
Remove-Item -LiteralPath $resolved -Recurse -Force
