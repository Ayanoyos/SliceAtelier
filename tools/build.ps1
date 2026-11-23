$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$extensionDir = Join-Path $projectDir 'extension'
$outputDir = Join-Path $projectDir 'dist'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $extensionDir 'package.json') -Raw | ConvertFrom-Json
$outputFile = Join-Path $outputDir ("SliceAtelier-" + $manifest.version + '.aseprite-extension')
Add-Type -AssemblyName System.IO.Compression
$stream = [System.IO.File]::Open($outputFile, [System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $extensionDir -File) {
        $entry = $archive.CreateEntry($file.Name)
        $inputStream = [System.IO.File]::OpenRead($file.FullName)
        $entryStream = $entry.Open()
        try { $inputStream.CopyTo($entryStream) }
        finally { $entryStream.Dispose(); $inputStream.Dispose() }
    }
}
finally { $archive.Dispose(); $stream.Dispose() }
Write-Output $outputFile
