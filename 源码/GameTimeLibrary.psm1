function Find-GameTimeEntries {
    param([string]$Root = 'G:\APP')
    if (!(Test-Path -LiteralPath $Root)) { return }
    foreach ($folder in Get-ChildItem -LiteralPath $Root -Directory) {
        $files = @(Get-ChildItem -LiteralPath $folder.FullName -Filter '*.exe' -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notmatch '(?i)unins|setup|install|crash|redist|vcredist|dxsetup|trial|report|helper|benchmark' -and $_.FullName -notmatch '(?i)\\(Engine|_CommonRedist|DirectX|Installer|Support)\\'
        })
        if (!$files.Count) { continue }
        $known = switch -Regex ($folder.Name) {
            '^It[ ._-]*Takes[ ._-]*Two$' { @{Name='双人成行';Exe='ItTakesTwo.exe';Art='it-takes-two'}; break }
            '^Chained[ ._-]*Together$' { @{Name='链在一起';Exe='ChainedTogether-Win64-Shipping.exe';Art='chained-together'}; break }
            default { $null }
        }
        $entry = $null
        if ($known) { $entry = $files | Where-Object Name -EQ $known.Exe | Select-Object -First 1 }
        if (!$entry) {
            # Prefer the root launcher, then a shipping build. Leave ambiguous folders for manual import.
            $rootFiles = @($files | Where-Object DirectoryName -EQ $folder.FullName)
            if ($rootFiles.Count -eq 1) { $entry=$rootFiles[0] }
            elseif ($files.Count -eq 1) { $entry=$files[0] }
            else { $shipping=@($files | Where-Object Name -Match 'Shipping.exe$'); if ($shipping.Count -eq 1) { $entry=$shipping[0] } }
        }
        if (!$entry) { continue }
        [pscustomobject]@{ Name=$(if($known){$known.Name}else{$folder.Name}); Path=$entry.FullName; Directory=$folder.FullName; WorkingDir=$entry.DirectoryName; Art=$(if($known){$known.Art}else{''}) }
    }
}

function OnApplicationStarted {
    try {
        foreach ($entry in Find-GameTimeEntries) {
            $existing = $PlayniteApi.Database.Games | Where-Object { @($_.GameActions | Where-Object Path -EQ $entry.Path).Count -gt 0 } | Select-Object -First 1
            if ($existing) {
                $art = Join-Path $PSScriptRoot ('art\'+$entry.Art+'.jpg')
                if (!$existing.CoverImage -and $entry.Art -and (Test-Path $art)) {
                    $existing.CoverImage=$PlayniteApi.Database.AddFile($art,$existing.Id)
                    $PlayniteApi.Database.Games.Update($existing)
                }
                continue
            }
            $game = New-Object Playnite.SDK.Models.Game
            $game.Name=$entry.Name
            $game.InstallDirectory=$entry.Directory
            $game.IsInstalled=$true
            $action = New-Object Playnite.SDK.Models.GameAction
            $action.Name='开始游戏'
            $action.Type=[Playnite.SDK.Models.GameActionType]::File
            $action.Path=$entry.Path
            $action.WorkingDir=$entry.WorkingDir
            $action.IsPlayAction=$true
            $game.GameActions = New-Object 'System.Collections.ObjectModel.ObservableCollection[Playnite.SDK.Models.GameAction]'
            $game.GameActions.Add($action)
            $PlayniteApi.Database.Games.Add($game)
            $art = Join-Path $PSScriptRoot ('art\'+$entry.Art+'.jpg')
            if ($entry.Art -and (Test-Path $art)) { $game.CoverImage=$PlayniteApi.Database.AddFile($art,$game.Id); $PlayniteApi.Database.Games.Update($game) }
            $__logger.Info("GameTime imported: $($entry.Name)")
        }
    } catch { $__logger.Error("GameTime import failed: $_") }
    try {
        [Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'GameTime.RemoteBridge.dll')) | Out-Null
        $root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        $script:GameTimeRemoteBridge = New-Object GameTime.RemoteBridge($PlayniteApi, $root)
        $__logger.Info('GameTime remote bridge started')
    } catch { $__logger.Error("GameTime remote bridge failed: $_") }
}

function OnApplicationStopped {
    if ($script:GameTimeRemoteBridge) { $script:GameTimeRemoteBridge.Dispose() }
}
