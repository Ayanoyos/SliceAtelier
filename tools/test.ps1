param([string]$Aseprite = 'C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $Aseprite)) { throw "Aseprite executable not found: $Aseprite" }
New-Item -ItemType Directory -Path (Join-Path $projectDir 'artifacts') -Force | Out-Null
$oldProfile = $env:ASEPRITE_USER_FOLDER
$env:ASEPRITE_USER_FOLDER = Join-Path $projectDir '.test-profile'
New-Item -ItemType Directory -Path $env:ASEPRITE_USER_FOLDER -Force | Out-Null
Push-Location -LiteralPath $projectDir
try {
    $output = & $Aseprite --batch --script tools/test-launcher.lua 2>&1 | Out-String
    $output | Set-Content -LiteralPath (Join-Path $projectDir 'artifacts/test-results.txt') -Encoding utf8
    Write-Output $output
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'ALL \d+ TESTS PASSED' -or $output -match 'TEST FAILED') {
        throw 'Aseprite integration tests failed. See artifacts/test-results.txt.'
    }
}
finally { Pop-Location; $env:ASEPRITE_USER_FOLDER = $oldProfile }
