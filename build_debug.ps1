# Build script for FlexRun Android APK
Set-Location C:\FlexRun

# Get Flutter root
$flutterRoot = (Get-Command flutter.bat).Source | Split-Path | Split-Path
Write-Host "Using Flutter at: $flutterRoot"

# Set environment variable
$env:FLUTTER_ROOT = $flutterRoot

# Run build
flutter build apk --debug
