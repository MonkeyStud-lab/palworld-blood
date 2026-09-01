#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$ueCmdCandidates = @(
  "C:\Program Files\Epic Games\UE_5.1\Engine\Binaries\Win64\UnrealEditor-Cmd.exe",
  "C:\Program Files\Epic Games\UE_5.1\Engine\Binaries\Win64\UnrealEditor.exe"
)
$ue = $ueCmdCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ue) { throw "UE 5.1 not found. Install it from Epic Launcher first." }

$proj = "C:\Users\Carde\Projects\PalworldModdingKit\Pal.uproject"
$py = "C:\Users\Carde\Projects\palworld-blood-both\tools\create_bloodrelay_modactor.py"
if (-not (Test-Path $proj)) { throw "Missing $proj" }
if (-not (Test-Path $py)) { throw "Missing $py" }

Write-Host "Launching Unreal to scaffold BloodRelay ModActor..."
Write-Host "NOTE: First kit compile can take 30-90+ minutes and requires Wwise integration."
Start-Process -FilePath $ue -ArgumentList @(
  "`"$proj`"",
  "-ExecutePythonScript=`"$py`""
)
