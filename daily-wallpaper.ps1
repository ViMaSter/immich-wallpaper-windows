[CmdletBinding()]
param(
    [ValidateSet("refresh", "scheduled", "logon")]
    [string]$Reason = "refresh",
    [switch]$Install,
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TaskPrefix = "Immich Wallpaper"
$ScriptPath = $PSCommandPath
$DataDirectory = Join-Path $env:LOCALAPPDATA "ImmichWallpaper"
$LogPath = Join-Path $DataDirectory "wallpaper.log"

function Write-Log([string]$Message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $LogPath -Value "[$timestamp] $Message"
}

function Get-WallpaperUrl {
    $hostName = [Environment]::GetEnvironmentVariable("IMMICH_HOST", "User")
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        $hostName = $env:IMMICH_HOST
    }
    $token = [Environment]::GetEnvironmentVariable("IMMICH_TOKEN", "User")
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $env:IMMICH_TOKEN
    }

    if ([string]::IsNullOrWhiteSpace($hostName) -or [string]::IsNullOrWhiteSpace($token)) {
        throw "IMMICH_HOST and IMMICH_TOKEN must be set."
    }

    $hostName = $hostName.TrimEnd("/")
    if ($hostName -notmatch "^https?://") {
        $hostName = "https://$hostName"
    }

    $encodedToken = [Uri]::EscapeDataString($token)
    return "$hostName/?height=9&width=16&token=$encodedToken&darken=60&border=0.1&topOffset=-0.2"
}

function Set-DesktopWallpaper([string]$Path) {
    if (-not ("ImmichWallpaper.NativeMethods" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace ImmichWallpaper {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern bool SystemParametersInfo(
            uint action, uint parameter, string imagePath, uint flags);
    }
}
"@
    }

    if (-not [ImmichWallpaper.NativeMethods]::SystemParametersInfo(20, 0, $Path, 3)) {
        throw "Windows could not apply the downloaded wallpaper."
    }
}

function Install-Tasks {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Reason scheduled"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
    $dailyTrigger = New-ScheduledTaskTrigger -Daily -At "00:01"
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn

    Register-ScheduledTask -TaskName "$TaskPrefix (Daily)" -Action $action `
        -Trigger $dailyTrigger -Settings $settings -Description "Refresh the Immich wallpaper daily." -Force | Out-Null
    Register-ScheduledTask -TaskName "$TaskPrefix (Logon)" -Action $action `
        -Trigger $logonTrigger -Settings $settings -Description "Refresh the Immich wallpaper at logon." -Force | Out-Null
    Write-Host "Installed daily and logon scheduled tasks."
}

function Uninstall-Tasks {
    Unregister-ScheduledTask -TaskName "$TaskPrefix (Daily)" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "$TaskPrefix (Logon)" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed daily and logon scheduled tasks."
}

if ($Install -and $Uninstall) {
    throw "Choose either -Install or -Uninstall, not both."
}

if ($Install) {
    New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    Install-Tasks
    exit 0
}

if ($Uninstall) {
    Uninstall-Tasks
    exit 0
}

New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
$mutex = New-Object System.Threading.Mutex($false, "Local\ImmichWallpaperRefresh")
$mutexAcquired = $false
try {
    if (-not $mutex.WaitOne(0)) {
        Write-Log "Skipped $Reason refresh because another refresh is running."
        exit 0
    }
    $mutexAcquired = $true

    $temporaryPath = Join-Path $DataDirectory "wallpaper-$([guid]::NewGuid()).tmp"
    $outputPath = Join-Path $DataDirectory "wallpaper-$(Get-Date -Format yyyy-MM-dd).png"
    try {
        Write-Log "Starting $Reason refresh."
        Invoke-WebRequest -Uri (Get-WallpaperUrl) -OutFile $temporaryPath -UseBasicParsing
        $bytes = [IO.File]::ReadAllBytes($temporaryPath)
        $pngHeader = @(137, 80, 78, 71, 13, 10, 26, 10)
        $validPng = $bytes.Length -ge $pngHeader.Count
        for ($i = 0; $validPng -and $i -lt $pngHeader.Count; $i++) {
            $validPng = $bytes[$i] -eq $pngHeader[$i]
        }
        if (-not $validPng) {
            throw "The server response was not a PNG image."
        }

        Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
        Set-DesktopWallpaper $outputPath
        Write-Log "Applied wallpaper $outputPath."
    } finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Log "Refresh failed: $($_.Exception.Message)"
    throw
} finally {
    if ($mutexAcquired) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
