[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$BackupPath,
    [string]$ConfigPath = (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'DesignCraft\ui.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\Theme.psm1') -Force
if ($PSCmdlet.ShouldProcess($ConfigPath, 'Restore the saved DesignCraft UI configuration')) {
    Assert-DcClosed
    Restore-DcThemeFile -BackupPath $BackupPath -ConfigPath $ConfigPath
    Write-Output 'Restored. Open DesignCraft to reload your previous settings.'
}
