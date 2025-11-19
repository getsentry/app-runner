# Vendored Dependencies

This directory contains third-party dependencies bundled directly in the repository.

## Sentry PowerShell Module

**Version**: 0.4.0
**Source**: [getsentry/sentry-powershell](https://github.com/getsentry/sentry-powershell)
**Release**: [v0.4.0](https://github.com/getsentry/sentry-powershell/releases/tag/0.4.0)
**License**: MIT

**Note**: The `lib/net462` directory has been removed from this bundle. This toolkit requires **PowerShell Core 7+** (not Windows PowerShell 5.1) for all functionality including telemetry.

### Why Bundled?

The Sentry PowerShell module is bundled rather than installed from PSGallery to ensure:

1. **Reliability** - No dependency on PSGallery availability during CI runs or in isolated environments
2. **Consistency** - All developers and CI environments use the exact same version
3. **Offline Support** - Works in air-gapped or restricted network environments
4. **Performance** - No first-run installation delay or network overhead
5. **Simplicity** - Zero setup required for telemetry functionality

Since this toolkit is internal Sentry testing infrastructure, bundling the module provides the best developer experience with guaranteed availability.

### Updating the Module

To update to a newer version:

1. Download the `Sentry.zip` artifact from the [releases page](https://github.com/getsentry/sentry-powershell/releases)
2. Extract to a temporary location
3. Replace the contents of `vendor/Sentry/` with the new version
4. Update the version number in this README
5. Test that telemetry still works with the new version
6. Commit the changes

```powershell
# Example update process
$version = "0.5.0"
curl -L -o Sentry.zip "https://github.com/getsentry/sentry-powershell/releases/download/$version/Sentry.zip"
Remove-Item -Recurse -Force vendor/Sentry
Expand-Archive -Path Sentry.zip -DestinationPath vendor/Sentry
Remove-Item Sentry.zip

# Remove Windows PowerShell assemblies (not supported)
Remove-Item -Recurse -Force vendor/Sentry/lib/net462
```

### Contents

- `Sentry.psd1` - PowerShell module manifest
- `Sentry.psm1` - Main module file
- `assemblies-loader.ps1` - .NET assembly loader
- `lib/net8.0/` - .NET 8.0 assemblies (for PowerShell 7.4+)
- `lib/net9.0/` - .NET 9.0 assemblies (for future PowerShell versions)
- `public/` - Public cmdlets (Start-Sentry, Out-Sentry, Add-SentryBreadcrumb, etc.)
- `private/` - Internal implementation files

**Note**: `lib/net462` (Windows PowerShell) has been removed as this toolkit requires PowerShell Core 7+.

### Size

Approximately 1.6 MB (PowerShell Core assemblies only; net462 removed)
