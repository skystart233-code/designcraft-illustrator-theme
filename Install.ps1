[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath = (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'DesignCraft\ui.json'),
    [ValidateSet('keep', 'zh', 'en')][string]$Language = 'keep',
    [switch]$LayoutOnly
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\Theme.psm1') -Force
$theme = Read-DcJson (Join-Path $PSScriptRoot 'theme\illustrator-style.json')
if ($PSCmdlet.ShouldProcess($ConfigPath, 'Install Illustrator-style workspace and save a backup')) {
    Assert-DcClosed
    $result = Install-DcThemeFile -ConfigPath $ConfigPath -Theme $theme -Language $Language -LayoutOnly:$LayoutOnly
    Write-Output ('Installed workspace: ' + $result.Workspace)
    Write-Output ('Backup: ' + $result.BackupPath)
    Write-Output 'Open DesignCraft to use the preset. Keep the backup path for Restore.ps1.'
}
