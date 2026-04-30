<#
.SYNOPSIS
  Stops the local Mule runtime (kills java + wrapper.exe spawned by mule.bat).
#>

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "==> Stopping Mule runtime processes..." -ForegroundColor Cyan

Get-Process -Name 'wrapper-windows-x86-64','wrapper' | ForEach-Object {
  Write-Host "Stopping wrapper PID $($_.Id)"
  Stop-Process -Id $_.Id -Force
}

Get-Process -Name 'java' | ForEach-Object {
  $cmdline = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
  if ($cmdline -match 'mule|wrapper') {
    Write-Host "Stopping java PID $($_.Id)"
    Stop-Process -Id $_.Id -Force
  }
}

Write-Host "Done." -ForegroundColor Green
