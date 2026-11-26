# Full verification of the desktop project (Windows).
# Usage from the project folder:   powershell -ExecutionPolicy Bypass -File tool\verify.ps1:   powershell -ExecutionPolicy Bypass -File tool\verify.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Step($title, [scriptblock]$command) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
    & $command
    if ($LASTEXITCODE -ne 0) {
        Write-Host "فشلت الخطوة: $title" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Step 'flutter pub get'            { flutter pub get }
Step 'تنسيق الكود (dart format)'  { dart format lib test }
Step 'التحليل (flutter analyze)'  { flutter analyze --fatal-infos }
Step 'الاختبارات (flutter test)'  { flutter test }

Write-Host ""
Write-Host "كل الخطوات نجحت." -ForegroundColor Green
