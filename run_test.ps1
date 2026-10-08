Set-Location C:\Repos\the-game
$g = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$lc = & $g --headless --path "C:\Repos\the-game" res://tests/load_check.tscn 2>&1 | Out-String
($lc -split "`n" | Where-Object { $_ -match 'OK:|FALHOU|^\s+res://' }) | ForEach-Object { $_.Trim() }
Write-Output "=== compila ==="
Remove-Item -Recurse -Force "$env:APPDATA\Godot\app_userdata\the-game" -ErrorAction SilentlyContinue
$o = & $g --path "C:\Repos\the-game" --rendering-driver opengl3 res://tests/shot.tscn -- 3 0 0 994 2>&1
$o | Select-String "SCRIPT ERROR|ERROR:|FALHOU|OK:|fim do farm|DEBUG mob" | Select-Object -First 24 | ForEach-Object { $_.Line }
$names = @("shot_run_110","shot_run_200","shot_bolt_1","shot_bolt_2")
foreach ($n in $names) {
  $src = "$env:APPDATA\Godot\app_userdata\the-game\$n.png"
  if (Test-Path $src) { Copy-Item $src "$env:TEMP\opencode\$n.png" -Force; Write-Output "salvou $n" }