[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$addonPath = Join-Path $root 'EVILRises'
$tocPath = Join-Path $addonPath 'EVILRises.toc'
$versionLines = @(Select-String -LiteralPath $tocPath -Pattern '^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$')
if ($versionLines.Count -ne 1) {
    throw 'EVILRises.toc must contain one numeric major.minor.patch version.'
}

$version = $versionLines[0].Matches[0].Groups[1].Value
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$archive = Join-Path $dist "EVILRises-$version-forever.zip"
Compress-Archive -LiteralPath $addonPath -DestinationPath $archive -Force
Get-Item -LiteralPath $archive
