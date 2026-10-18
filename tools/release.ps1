# release.ps1 -- build what a player installs.
#
#   .\tools\release.ps1            -> dist\zugzugleveler-setup.exe  (double-click: installs everything)
#                                     dist\ZugzugLeveler-<version>.zip (the addon alone, for CurseForge/Wago)
#
# The setup program is the companion built with the addon packed inside
# (companion/bundle.go, -tags bundle). It finds World of Warcraft, copies the
# addon into each game folder, puts the companion in %LOCALAPPDATA%\zugzugleveler\bin,
# makes it start with Windows and opens the page. `-uninstall` undoes it.
# Never packed: anything not in ZugzugLeveler\ (AnglicanText may not be published,
# and is not in the repo).
param([string]$Version = (Get-Date -Format 'yyyy.MM.dd'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$addon = Join-Path $root 'ZugzugLeveler'
$bundle = Join-Path $root 'companion\bundle\ZugzugLeveler'
$dist = Join-Path $root 'dist'

# the addon must pass its tests first
& luajit (Join-Path $root 'test\harness.lua') $addon | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw 'addon tests failed' }

if (Test-Path (Split-Path $bundle)) { Remove-Item -Recurse -Force (Split-Path $bundle) }
New-Item -ItemType Directory -Force $bundle | Out-Null
Copy-Item -Recurse "$addon\*" $bundle
New-Item -ItemType Directory -Force $dist | Out-Null

Push-Location (Join-Path $root 'companion')
try {
  go test ./...
  if ($LASTEXITCODE -ne 0) { throw 'companion tests failed' }
  go build -tags bundle -ldflags "-s -w" -o (Join-Path $dist 'zugzugleveler-setup.exe') .
  if ($LASTEXITCODE -ne 0) { throw 'go build failed' }
} finally { Pop-Location }

$zip = Join-Path $dist "ZugzugLeveler-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $addon -DestinationPath $zip
Remove-Item -Recurse -Force (Split-Path $bundle)

Get-ChildItem $dist | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize
Write-Host "Send dist\zugzugleveler-setup.exe. Windows shows 'Windows protected your PC' for an unsigned program: More info -> Run anyway."
