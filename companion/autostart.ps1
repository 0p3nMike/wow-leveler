# Start the companion's game watcher at Windows logon, so the page opens
# whenever WoW starts. Addons cannot start programs, so this is how the
# companion "launches with the game".
#
#   .\autostart.ps1          build the watcher, add it to Startup, start it now
#   .\autostart.ps1 -Remove  stop it and take it out of Startup
param([switch]$Remove)
$ErrorActionPreference = 'Stop'

$exe  = Join-Path $PSScriptRoot 'sl0pleveler-watch.exe'
$link = Join-Path ([Environment]::GetFolderPath('Startup')) 'sl0p.leveler companion.lnk'

Get-Process sl0pleveler-watch -ErrorAction SilentlyContinue | Stop-Process -Force

if ($Remove) {
    if (Test-Path $link) { Remove-Item $link }
    Write-Host 'Removed the watcher from Startup and stopped it.'
    return
}

# -H=windowsgui: no console window for the background copy.
Push-Location $PSScriptRoot
try { go build -ldflags '-H=windowsgui' -o $exe . } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw 'go build failed' }

$s = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
$s.TargetPath = $exe
$s.Arguments = '-watch'
$s.WorkingDirectory = $PSScriptRoot
$s.Description = 'Opens the sl0p.leveler page when WoW starts'
$s.Save()

Start-Process $exe -ArgumentList '-watch' -WorkingDirectory $PSScriptRoot
Write-Host "Watching for the game. Startup shortcut: $link"
