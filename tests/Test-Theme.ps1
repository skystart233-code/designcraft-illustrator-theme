param([string]$TestRoot = (Join-Path ([IO.Path]::GetTempPath()) ('dc-theme-test-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '..\scripts\Theme.psm1') -Force
$theme = Read-DcJson (Join-Path $PSScriptRoot '..\theme\illustrator-style.json')
$script:checks = 0
function Assert-Theme([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
$current = @{
    language = 'fr'
    brightness = 'Light'
    scripts = ,@('Personal macro', 'keep-original-text')
    futureSetting = @{ value = 'preserve-me' }
    customWorkspaces = @(@{ name = 'My workspace'; controlBar = $false })
    shortcuts = @{}
    shortcutSets = @{
        version = 1
        active = 'My keys'
        sets = @(@{
            name = 'My keys'
            overrides = @(
                @{ command = 'custom.keep'; keys = @('Cmd+Alt+K') },
                @{ command = 'custom.conflict'; keys = @('Cmd+D') }
            )
        })
    }
}
$merged = Merge-DcTheme -Current $current -Theme $theme
Assert-Theme ($merged.language -eq 'fr') 'Default installation changed the interface language.'
Assert-Theme ($merged.futureSetting.value -eq 'preserve-me') 'An unrelated setting was lost.'
Assert-Theme ($merged.scripts[0][1] -eq 'keep-original-text') 'A user script was modified.'
Assert-Theme ($current.brightness -eq 'Light') 'Merge mutated its input.'
Assert-Theme (@($merged.customWorkspaces | Where-Object { $_.name -eq 'My workspace' }).Count -eq 1) 'Existing workspace was lost.'
Assert-Theme ($merged.shortcutSets.active -eq 'Illustrator-style') 'The theme shortcut set was not selected.'
$active = @($merged.shortcutSets.sets | Where-Object { $_.name -eq 'Illustrator-style' })[0]
$keep = @($active.overrides | Where-Object { $_.command -eq 'custom.keep' })[0]
$conflict = @($active.overrides | Where-Object { $_.command -eq 'custom.conflict' })[0]
Assert-Theme ($keep.keys[0] -eq 'Cmd+Alt+K') 'An unrelated custom binding was lost.'
Assert-Theme ($conflict.keys.Count -eq 0) 'A competing custom binding was left active.'
$original = @($merged.shortcutSets.sets | Where-Object { $_.name -eq 'My keys' })[0]
Assert-Theme ($original.overrides[1].keys[0] -eq 'Cmd+D') 'The original shortcut set was changed.'
Assert-Theme ($merged.shortcuts['object.lock'] -eq 'Cmd+2') 'Lock mapping was not applied.'
$twice = Merge-DcTheme -Current $merged -Theme $theme
Assert-Theme (@($twice.customWorkspaces | Where-Object { $_.name -eq 'Illustrator-style' }).Count -eq 1) 'Repeated installation duplicates workspaces.'
Assert-Theme (@($twice.shortcutSets.sets | Where-Object { $_.name -eq 'Illustrator-style' }).Count -eq 1) 'Repeated installation duplicates shortcut sets.'
$layout = Merge-DcTheme -Current $current -Theme $theme -LayoutOnly
Assert-Theme ($layout.shortcutSets.active -eq 'My keys') 'LayoutOnly changed the keymap.'
$chinese = Merge-DcTheme -Current $current -Theme $theme -Language zh
Assert-Theme ($chinese.language -eq 'zh') 'Explicit Chinese language setting failed.'
$blank = Merge-DcTheme -Current @{} -Theme $theme
Assert-Theme ($blank.controlBar -and $blank.toolsDoubleColumn) 'Installing on a fresh configuration failed.'
$invalid = Read-DcJson (Join-Path $PSScriptRoot '..\theme\illustrator-style.json')
$invalid.settings['scripts'] = @('unwanted-script')
$rejected = $false
try { $null = Merge-DcTheme -Current $current -Theme $invalid } catch { $rejected = $true }
Assert-Theme $rejected 'The theme accepted a setting outside its allowlist.'

[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($TestRoot)) | Out-Null
$config = Join-Path $TestRoot 'ui.json'
$originalText = '{"language":"fr", "unrelated":"preserved", "customWorkspaces":[]}'
[IO.File]::WriteAllText($config, $originalText, (New-Object Text.UTF8Encoding($false)))
$result = Install-DcThemeFile -ConfigPath $config -Theme $theme
Assert-Theme ([IO.File]::ReadAllText($result.BackupPath) -ceq $originalText) 'Backup is not an exact copy.'
$installed = Read-DcJson $config
Assert-Theme ($installed.unrelated -eq 'preserved' -and $installed.shortcuts['object.lock'] -eq 'Cmd+2') 'Written configuration is incorrect.'
Restore-DcThemeFile -BackupPath $result.BackupPath -ConfigPath $config
Assert-Theme ([IO.File]::ReadAllText($config) -ceq $originalText) 'Restore did not reproduce the original file.'
$broken = Join-Path $TestRoot 'broken.bak'
[IO.File]::WriteAllText($broken, '{invalid')
$rejected = $false
try { Restore-DcThemeFile -BackupPath $broken -ConfigPath $config } catch { $rejected = $true }
Assert-Theme ($rejected -and [IO.File]::ReadAllText($config) -ceq $originalText) 'Malformed backup modified the current file.'
Write-Output ("Passed $script:checks checks on PowerShell " + $PSVersionTable.PSVersion)
