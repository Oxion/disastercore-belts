$modName = 'disastercore-belts'
$targetPath = Join-Path (Join-Path $env:APPDATA 'Factorio\mods') $modName

if (Test-Path $targetPath) {
    Remove-Item $targetPath -Force -NoRecurse
    Write-Host "Symlink removed successfully!" -ForegroundColor Green
} else {
    Write-Host "Symlink does not exist" -ForegroundColor Yellow
}
