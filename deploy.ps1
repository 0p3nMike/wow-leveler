# deploy.ps1 -- link the addon into a WoW client's AddOns folder.
#
#   .\deploy.ps1                 # the Forever beta (_classic_beta_, 1.60.1)
#   .\deploy.ps1 -Client _forever_   # whatever folder the live client uses at launch
#
# A junction, never a copy: edit here, /reload in game. A brand-new addon
# (first deploy) needs the game restarted before it shows in the AddOns list.
param(
  [string]$Client = "_classic_beta_",
  [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft"
)
$ErrorActionPreference = "Stop"

$src = Join-Path $PSScriptRoot "ZugzugLeveler"
$clientDir = Join-Path $WowRoot $Client
if (-not (Test-Path $clientDir)) {
  $have = (Get-ChildItem $WowRoot -Directory | Where-Object Name -like "_*_" | ForEach-Object Name) -join ", "
  throw "no client folder $clientDir (have: $have)"
}
$flavor = Get-Content (Join-Path $clientDir ".flavor.info") -ErrorAction SilentlyContinue | Select-Object -Last 1
$addons = Join-Path $clientDir "Interface\AddOns"
New-Item -ItemType Directory -Force $addons | Out-Null
$dst = Join-Path $addons "ZugzugLeveler"

# the addon was called SlopLeveler until 2026-10-18: drop that old junction if it
# points into this checkout (rmdir removes the link itself, never what it points at)
$old = Join-Path $addons "SlopLeveler"
if (Test-Path -LiteralPath $old) {
  $o = Get-Item -LiteralPath $old -Force
  if ($o.LinkType -eq "Junction" -and "$($o.Target)" -like "$PSScriptRoot*") {
    cmd /c rmdir "$old"
    Write-Output "removed the old link: $old"
  }
}

if (Test-Path $dst) {
  $item = Get-Item $dst -Force
  if ($item.LinkType -eq "Junction" -and ($item.Target -contains $src -or $item.Target -eq $src)) {
    Write-Output "already linked: $dst -> $src ($flavor)"
    exit 0
  }
  throw "$dst exists and is not our junction (LinkType=$($item.LinkType), Target=$($item.Target)); move it away first"
}

New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
Write-Output "linked: $dst -> $src ($flavor)"
if (Get-Process -Name "WowB", "Wow", "WowClassic" -ErrorAction SilentlyContinue) {
  Write-Output "WoW is running: restart it once so the new addon is picked up; after that /reload is enough."
}
