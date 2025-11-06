# App Runner

PowerShell automation toolkit for application deployment, lifecycle management, and diagnostics collection across multiple target platforms.

## Overview

This repository contains PowerShell modules for automating application testing and diagnostics:

- **[app-runner](./app-runner)** - Platform lifecycle management, app deployment, and diagnostics collection
- **[sentry-api-client](./sentry-api-client)** - Sentry REST API client for event retrieval and CLI operations

## Supported Platforms

Currently supported:
- Xbox (One, Series X/S)
- PlayStation 5
- Nintendo Switch

Future support planned:
- Mobile platforms (iOS, Android)
- Desktop platforms (Windows, macOS, Linux)

## Telemetry

This toolkit automatically collects operational telemetry using [Sentry](https://sentry.io) to improve reliability and diagnose issues. Telemetry helps identify test infrastructure failures, device connection problems, and automation bottlenecks.

### What's Collected

Examples of the types of telemetry data collected:

- Module errors and exceptions with context (platform, session ID, error category)
- Device connection failures and lock acquisition issues
- Test infrastructure problems (missing event captures, polling timeouts)
- Diagnostic operation breadcrumbs showing the sequence of operations leading to failures
- Performance metrics for critical operations (device connections, app deployments)

### Privacy & Control

**Telemetry is optional, enabled by default, and controllably by environment variable:**

**To disable telemetry completely:**
```powershell
$env:SENTRY_DSN = $null  # or empty string
```

**To use your own Sentry project:**
```powershell
$env:SENTRY_DSN = 'https://your-key@o123.ingest.sentry.io/your-project'
```

**Note:** DSNs are public client keys that are safe to expose in code or configuration.
They cannot be used to access your Sentry account or data.
See [Sentry DSN documentation](https://docs.sentry.io/product/sentry-basics/dsn-explainer/) for details.

### Dependencies

Telemetry requires the optional `Sentry` PowerShell module:

```powershell
Install-Module -Name Sentry -Repository PSGallery -Force
```

If the module is not installed, telemetry is automatically disabled and all functionality works normally. The toolkit has no hard dependency on Sentry.

**Learn more:** [sentry-powershell on GitHub](https://github.com/getsentry/sentry-powershell)

## Requirements

### Platform-Specific Prerequisites

**Important:** Using this toolkit to run applications on target platforms requires:

1. **Valid development agreements** with the respective platform holders (Microsoft, Sony, Nintendo, Apple, Google, etc.)
2. **Licensed access to platform SDKs** and development tools
3. **Authorized development hardware** (devkits, testflight access, etc.) where applicable
4. **Compliance with platform holder NDAs** and terms of service

### General Requirements

- PowerShell 7.0 or later
- Appropriate platform SDKs installed and configured
- Platform-specific environment variables set (see individual module documentation)

## Getting Started

See individual module READMEs for detailed usage:

- [SentryAppRunner Module](./app-runner/README.md)
- [SentryApiClient Module](./sentry-api-client/README.md)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development standards and testing requirements.

## License

MIT License - See [LICENSE](./LICENSE) for details.
