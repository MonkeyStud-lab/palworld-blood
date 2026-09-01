#Requires -Version 5.1
<#
.SYNOPSIS
  Installs what can be automated for Palworld LogicMod / BloodRelay setup.
.NOTES
  UE 5.1, VS 2022, and Wwise still need GUI + accounts. See docs/SETUP_LOGICMOD.md
#>

$ErrorActionPreference = "Continue"
$KitPath = "C:\Users\Carde\Projects\PalworldModdingKit"
$BloodRelayContent = Join-Path $KitPath "Content\Mods\BloodRelay"

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

Write-Step "Disk space"
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host "C: free = $freeGB GB (need ~50-80 GB for full UE+kit)"

Write-Step ".NET 6 SDK"
$sdk = & dotnet --list-sdks 2>$null
if ($sdk -match "^6\.") {
  Write-Host "Already installed:`n$sdk"
} else {
  winget install --id Microsoft.DotNet.SDK.6 -e --accept-source-agreements --accept-package-agreements
}

Write-Step "Epic Games Launcher"
$epic = @(
  "$env:ProgramFiles(x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe",
  "$env:ProgramFiles\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($epic) {
  Write-Host "Found: $epic"
} else {
  winget install --id EpicGames.EpicGamesLauncher -e --accept-source-agreements --accept-package-agreements
}

Write-Step "Clone PalworldModdingKit"
if (-not (Test-Path (Join-Path $KitPath "Pal.uproject"))) {
  if (Test-Path $KitPath) { Remove-Item -Recurse -Force $KitPath }
  git clone --depth 1 https://github.com/localcc/PalworldModdingKit.git $KitPath
} else {
  Write-Host "Already present: $KitPath"
}

Write-Step "Scaffold Content/Mods/BloodRelay"
New-Item -ItemType Directory -Force -Path $BloodRelayContent | Out-Null
$readme = Join-Path $BloodRelayContent "README_CREATE_MODACTOR.txt"
@"
Create these assets IN UNREAL EDITOR (Content Browser -> this folder):

1) Blueprint Class (Actor) named exactly: ModActor
2) Miscellaneous -> Data Asset -> PrimaryAssetLabel
   - Chunk ID: 778
   - Cook Rule: Always Cook
   - Label Assets in My Directory: checked

Then add Blueprint Callable functions on ModActor:
  SpawnHitBlood(Location, Direction, Scale)
  SpawnGroundBlood(Location, Direction, Count, Size)
  SpawnBloodPoolAt(Location, bHeadshot)
  SpawnHeadGoreAt(Location)

Full graph rules: palworld-blood-both/docs/BP_RELAY.md
Full install: palworld-blood-both/docs/SETUP_LOGICMOD.md
"@ | Set-Content -Path $readme -Encoding UTF8
Write-Host "Wrote $readme"

Write-Step "Status checklist"
$checks = [ordered]@{
  "dotnet6" = (& dotnet --list-sdks 2>$null) -match "^6\."
  "epicLauncher" = [bool]$epic -or (Test-Path "$env:ProgramFiles(x86)\Epic Games\Launcher")
  "ue51" = Test-Path "C:\Program Files\Epic Games\UE_5.1\Engine\Binaries\Win64\UnrealEditor.exe"
  "vs2022" = Test-Path "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
  "moddingKit" = Test-Path (Join-Path $KitPath "Pal.uproject")
  "bloodRelayFolder" = Test-Path $BloodRelayContent
}
$checks.GetEnumerator() | ForEach-Object {
  $mark = if ($_.Value) { "OK" } else { "MISSING" }
  Write-Host ("  [{0}] {1}" -f $mark, $_.Key)
}

Write-Host "`nNext: install VS 2022 + UE 5.1 + Wwise (see docs/SETUP_LOGICMOD.md), then open Pal.uproject"
if (Test-Path (Join-Path $KitPath "Pal.uproject")) {
  Write-Host "Kit path: $KitPath\Pal.uproject"
}
