# immich-wallpaper-windows

Automatically sets a random photo from an [Immich](https://immich.app/) instance
as the Windows desktop wallpaper every day and when the user logs in.

## Requirements

- Windows 10 or later
- PowerShell 5.1 or later
- An Immich API key with `asset.download` and `album.read` permissions

## Configuration

Set these user environment variables before installing the scheduled tasks:

```powershell
[Environment]::SetEnvironmentVariable("IMMICH_HOST", "your-immich-instance.example.com", "User")
[Environment]::SetEnvironmentVariable("IMMICH_TOKEN", "your-api-key", "User")
```

`IMMICH_HOST` may be a hostname or a full `https://` URL. The token is read only
when a refresh runs and is never written to the repository.

## Install

Run PowerShell in the cloned directory:

```powershell
.\daily-wallpaper.ps1 -Install
```

This creates a user logon task and a daily task at 00:01. Both tasks use
`-StartWhenAvailable`, so a missed daily run is performed when the computer is
available again. To refresh immediately:

```powershell
.\daily-wallpaper.ps1
```

The image is cached in
`$env:LOCALAPPDATA\ImmichWallpaper\wallpaper-YYYY-MM-DD.png` and applied to all
connected displays.

## Uninstall

```powershell
.\daily-wallpaper.ps1 -Uninstall
```

To remove the downloaded images and logs as well, delete
`$env:LOCALAPPDATA\ImmichWallpaper`.