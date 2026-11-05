[CmdletBinding()]
param(
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,5}$')]
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'Building the MSI requires Windows and the .NET 8 SDK.'
}

$parts = $Version.Split('.')
if ([int]$parts[0] -gt 255 -or [int]$parts[1] -gt 255 -or [int]$parts[2] -gt 65535) {
    throw 'MSI versions must be major.minor.build, with maximum values 255.255.65535.'
}

$sourceRoot = Split-Path $PSScriptRoot -Parent
$outputDirectory = Join-Path $sourceRoot 'artifacts'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Push-Location $sourceRoot
try {
    dotnet tool restore
    if ($LASTEXITCODE -ne 0) {
        throw "WiX tool restore failed with exit code $LASTEXITCODE."
    }

    dotnet tool run wix -- build "$PSScriptRoot\Package.wxs" `
        -arch x64 `
        -d "ProductVersion=$Version" `
        -d "SourceRoot=$sourceRoot" `
        -out "$outputDirectory\M365-BP-Baseline-$Version-x64.msi"
    if ($LASTEXITCODE -ne 0) {
        throw "WiX build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
