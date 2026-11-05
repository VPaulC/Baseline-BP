[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MsiPath
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'Installer tests require an elevated x64 PowerShell 7 session on Windows.'
}

$MsiPath = (Resolve-Path $MsiPath).Path
$sourceRoot = Split-Path $PSScriptRoot -Parent
$logDirectory = Join-Path $sourceRoot 'artifacts'
$installDirectory = Join-Path $env:ProgramFiles 'M365 BP Baseline'
$menuDirectory = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'M365 BP Baseline'

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Msi {
    param([string]$Arguments, [string]$LogName)
    $logPath = Join-Path $logDirectory $LogName
    $process = Start-Process msiexec.exe -ArgumentList "$Arguments /qn /norestart /L*v `"$logPath`"" -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "msiexec failed with exit code $($process.ExitCode). See $logPath."
    }
}

# Never overwrite an existing installation on a developer's machine.
Assert-Condition (-not (Test-Path $installDirectory)) "Test requires a clean machine: $installDirectory already exists."
Assert-Condition (-not (Test-Path $menuDirectory)) "Test requires a clean machine: $menuDirectory already exists."
Assert-Condition (-not (Test-Path 'HKLM:\Software\VPaulC\M365BPBaseline')) 'An installation registry key already exists.'

$installed = $false
try {
    Invoke-Msi "/i `"$MsiPath`"" 'install.log'
    $installed = $true

    foreach ($relativePath in @('README.md', 'scripts\deploy-m365-bp-baseline.ps1')) {
        $actual = Join-Path $installDirectory $relativePath
        Assert-Condition (Test-Path $actual) "Missing installed file: $actual"
        $expectedHash = (Get-FileHash (Join-Path $sourceRoot $relativePath)).Hash
        Assert-Condition ((Get-FileHash $actual).Hash -eq $expectedHash) "Installed payload differs: $relativePath"
    }

    $shell = New-Object -ComObject WScript.Shell
    $console = $shell.CreateShortcut((Join-Path $menuDirectory 'M365 BP Baseline - PowerShell.lnk'))
    Assert-Condition ($console.TargetPath -eq "$env:ProgramFiles\PowerShell\7\pwsh.exe") 'Console shortcut has the wrong PowerShell target.'
    Assert-Condition ($console.Arguments -eq '-NoLogo -NoProfile -NoExit') 'Console shortcut must not execute the deployment script.'
    Assert-Condition ($console.WorkingDirectory -eq $installDirectory) 'Console shortcut has the wrong working directory.'
    $documentation = $shell.CreateShortcut((Join-Path $menuDirectory 'M365 BP Baseline - Documentation.lnk'))
    Assert-Condition ($documentation.TargetPath -eq (Join-Path $installDirectory 'README.md')) 'Documentation shortcut has the wrong target.'
    Assert-Condition ((Get-ItemProperty 'HKLM:\Software\VPaulC\M365BPBaseline').Installed -eq 1) 'Installation registry marker is missing.'

    $parseErrors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $installDirectory 'scripts\deploy-m365-bp-baseline.ps1'),
        [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    Assert-Condition ($parseErrors.Count -eq 0) "Installed deployment script has parse errors: $parseErrors"

    # This selected step is offline and read-only; never apply tenant policies in CI.
    & "$env:ProgramFiles\PowerShell\7\pwsh.exe" -NoProfile -File `
        "$installDirectory\scripts\deploy-m365-bp-baseline.ps1" -ReviewLegacyAuth -SkipGraphConnection -DryRun
    Assert-Condition ($LASTEXITCODE -eq 0) 'Installed script failed its offline smoke test.'

    Invoke-Msi "/fa `"$MsiPath`"" 'repair.log'
    Assert-Condition (Test-Path "$installDirectory\scripts\deploy-m365-bp-baseline.ps1") 'Repair did not preserve the deployment script.'
}
finally {
    if ($installed) {
        Invoke-Msi "/x `"$MsiPath`"" 'uninstall.log'
    }
}

Assert-Condition (-not (Test-Path $installDirectory)) 'Uninstall left the installation directory behind.'
Assert-Condition (-not (Test-Path $menuDirectory)) 'Uninstall left Start menu shortcuts behind.'
Assert-Condition (-not (Test-Path 'HKLM:\Software\VPaulC\M365BPBaseline')) 'Uninstall left the installation registry key behind.'
Write-Host 'MSI installation, payload, shortcuts, offline execution, repair, and uninstall passed.'
