Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AllowedFields = @(
    'brightness', 'frameEdges', 'controlBar', 'toolsDoubleColumn', 'dockTab',
    'openPanel', 'floating', 'docking', 'dockingHidden', 'autoCollapseIconicPanels',
    'dockExpanded', 'iconGroups', 'taskBar', 'taskBarPin', 'workspace'
)

function ConvertTo-DcMap {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) { $result[$key] = ConvertTo-DcMap $Value[$key] }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-DcMap $property.Value
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-DcMap $item) }
        return ,$items
    }
    return $Value
}

function Read-DcJson {
    param([Parameter(Mandatory)][string]$Path)
    $text = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path), [Text.Encoding]::UTF8)
    $parsed = ConvertTo-DcMap (ConvertFrom-Json -InputObject $text)
    if ($parsed -isnot [hashtable]) { throw "Expected a JSON object: $Path" }
    return $parsed
}

function Write-DcJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][hashtable]$Value)
    $absolute = [IO.Path]::GetFullPath($Path)
    $parent = [IO.Path]::GetDirectoryName($absolute)
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = Join-Path $parent ('.theme-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $json = ConvertTo-Json -InputObject $Value -Depth 100
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    # The temp file is beside its target, so replacement stays on one filesystem.
    if ([IO.File]::Exists($absolute)) {
        [IO.File]::Replace($temporary, $absolute, [System.Management.Automation.Language.NullString]::Value)
    } else {
        [IO.File]::Move($temporary, $absolute)
    }
}

function Assert-DcClosed {
    if (Get-Process -Name designcraft -ErrorAction SilentlyContinue) {
        throw 'Close DesignCraft normally before installing or restoring this preset.'
    }
}

function Merge-DcTheme {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Current,
        [Parameter(Mandatory)][hashtable]$Theme,
        [ValidateSet('keep', 'zh', 'en')][string]$Language = 'keep',
        [switch]$LayoutOnly
    )
    if ($Theme.schemaVersion -ne 1) { throw 'Unsupported theme schema.' }
    if ($Theme.id -ne 'designcraft-illustrator-style') { throw 'Unexpected theme identifier.' }
    foreach ($key in $Theme.settings.Keys) {
        if ($key -notin $script:AllowedFields) { throw "Unsupported theme setting: $key" }
    }
    $copy = ConvertTo-DcMap (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Current -Depth 100))
    foreach ($key in $Theme.settings.Keys) { $copy[$key] = $Theme.settings[$key] }
    if ($Language -ne 'keep') { $copy['language'] = $(if ($Language -eq 'en') { '' } else { 'zh' }) }

    $workspaces = @()
    if ($copy.ContainsKey('customWorkspaces')) {
        $workspaces = @($copy.customWorkspaces | Where-Object { $_.name -ne $Theme.workspace.name })
    }
    $copy['customWorkspaces'] = @($workspaces) + @($Theme.workspace)

    if (-not $LayoutOnly) {
        $overrides = @{}
        $sets = @()
        if ($copy.ContainsKey('shortcuts')) {
            foreach ($key in $copy.shortcuts.Keys) {
                $value = $copy.shortcuts[$key]
                $overrides[$key] = @($(if ($value) { $value }))
            }
        }
        if ($copy.ContainsKey('shortcutSets')) {
            if ($copy.shortcutSets.version -ne 1) { throw 'Unsupported DesignCraft shortcut-set format.' }
            $sets = @($copy.shortcutSets.sets)
            $active = @($sets | Where-Object { $_.name -eq $copy.shortcutSets.active })
            if ($active.Count -gt 0) {
                foreach ($entry in $active[0].overrides) { $overrides[$entry.command] = @($entry.keys) }
            }
        }
        # Remove existing custom bindings that would compete with a theme binding.
        $claimed = @($Theme.shortcuts.Values | Where-Object { $_ })
        foreach ($command in @($overrides.Keys)) {
            if (-not $Theme.shortcuts.ContainsKey($command)) {
                $overrides[$command] = @($overrides[$command] | Where-Object { $_ -notin $claimed })
            }
        }
        foreach ($command in $Theme.shortcuts.Keys) {
            $value = $Theme.shortcuts[$command]
            $overrides[$command] = @($(if ($value) { $value }))
        }
        $entries = @()
        $legacy = @{}
        foreach ($command in @($overrides.Keys | Sort-Object)) {
            $keys = @($overrides[$command])
            $entries += @{ command = $command; keys = $keys }
            $legacy[$command] = $(if ($keys.Count) { $keys[0] } else { '' })
        }
        $sets = @($sets | Where-Object { $_.name -ne $Theme.shortcutSetName })
        $sets += @{ name = $Theme.shortcutSetName; overrides = $entries }
        $copy['shortcutSets'] = @{ version = 1; active = $Theme.shortcutSetName; sets = @($sets) }
        $copy['shortcuts'] = $legacy
    }
    return $copy
}

function Install-DcThemeFile {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][hashtable]$Theme,
        [ValidateSet('keep', 'zh', 'en')][string]$Language = 'keep',
        [switch]$LayoutOnly
    )
    $config = [IO.Path]::GetFullPath($ConfigPath)
    $existing = @{}
    if (Test-Path -LiteralPath $config) { $existing = Read-DcJson $config }
    $merged = Merge-DcTheme -Current $existing -Theme $Theme -Language $Language -LayoutOnly:$LayoutOnly
    $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-ffffff')
    $backup = $config + '.illustrator-style.' + $stamp + '.bak'
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($config)) | Out-Null
    if (Test-Path -LiteralPath $config) {
        [IO.File]::Copy($config, $backup, $false)
    } else {
        [IO.File]::WriteAllText($backup, '{}', (New-Object Text.UTF8Encoding($false)))
    }
    Write-DcJson -Path $config -Value $merged
    return @{ ConfigPath = $config; BackupPath = $backup; Workspace = $Theme.workspace.name }
}

function Restore-DcThemeFile {
    param([Parameter(Mandatory)][string]$BackupPath, [Parameter(Mandatory)][string]$ConfigPath)
    $backup = [IO.Path]::GetFullPath($BackupPath)
    $target = [IO.Path]::GetFullPath($ConfigPath)
    if ($backup -eq $target) { throw 'Backup and configuration must be different files.' }
    # Parse before touching the current file; a malformed backup never gets applied.
    $null = Read-DcJson $backup
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    $temporary = Join-Path ([IO.Path]::GetDirectoryName($target)) ('.restore-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::Copy($backup, $temporary, $false)
    if ([IO.File]::Exists($target)) { [IO.File]::Replace($temporary, $target, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temporary, $target) }
}

Export-ModuleMember -Function Read-DcJson, Write-DcJson, Merge-DcTheme, Assert-DcClosed, Install-DcThemeFile, Restore-DcThemeFile
