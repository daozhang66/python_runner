$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$version = (Get-Content -LiteralPath (Join-Path $projectRoot '.flutter-version') -Raw).Trim()
$flutter = Join-Path $projectRoot ".tooling/flutter-$version/bin/flutter.bat"
if (-not (Test-Path -LiteralPath $flutter)) {
    throw "Flutter $version is missing. Run: git clone --depth 1 --branch $version https://github.com/flutter/flutter.git .tooling/flutter-$version"
}
& $flutter @args
exit $LASTEXITCODE
