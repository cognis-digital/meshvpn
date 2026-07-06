<#
.SYNOPSIS
    meshvpn installer for Windows. meshvpn is a POSIX shell tool, so it runs
    under Git Bash / WSL / MSYS2 (any bash on PATH). This installer drops a
    small wrapper on your PATH that invokes meshvpn.sh with bash.
.PARAMETER Prefix
    Install root. Defaults to $env:LOCALAPPDATA\Programs\meshvpn.
#>
[CmdletBinding()]
param(
    [string] $Prefix = (Join-Path $env:LOCALAPPDATA 'Programs\meshvpn')
)
$ErrorActionPreference = 'Stop'

$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
    Write-Error "bash not found. meshvpn needs a POSIX shell (Git Bash, WSL, or MSYS2)."
    exit 1
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir = Join-Path $Prefix 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

# A .cmd wrapper so `meshvpn` works from PowerShell/cmd; it shells out to bash.
$wrapper = Join-Path $binDir 'meshvpn.cmd'
$target = (Join-Path $here 'meshvpn.sh')
"@echo off`r`nbash `"$target`" %*" | Set-Content -LiteralPath $wrapper -Encoding ASCII

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
    Write-Host "added $binDir to your user PATH (restart your shell to pick it up)"
}

Write-Host "installed: $wrapper -> $target"
Write-Host "try: meshvpn --help"
