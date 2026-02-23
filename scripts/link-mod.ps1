$modName = 'disastercore-belts'
$targetPath = Join-Path (Join-Path $env:APPDATA 'Factorio\mods') $modName
$sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'mod'

if (Test-Path $targetPath) {
    Write-Host "Symlink already exists at: $targetPath" -ForegroundColor Yellow
} else {
    try {
        $null = New-Item -ItemType SymbolicLink -Path $targetPath -Target $sourcePath -Force
        Write-Host "Symlink created successfully!" -ForegroundColor Green
        Write-Host "Mod installed to: $targetPath" -ForegroundColor Green
    } catch {
        Write-Host "Error creating symlink: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Note: You may need to run as Administrator or enable Developer Mode in Windows Settings" -ForegroundColor Yellow
        exit 1
    }
}
