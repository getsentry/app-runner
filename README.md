# App Runner

PowerShell automation toolkit for application deployment, lifecycle management, and diagnostics collection across multiple target platforms.

## Overview

This repository contains PowerShell modules for automating application testing and diagnostics:

- **[app-runner](./app-runner)** - Platform lifecycle management, app deployment, and diagnostics collection
- **[sentry-api-client](./sentry-api-client)** - Sentry REST API client for event retrieval and CLI operations

## Supported Platforms

Currently supported:

- **Gaming Consoles:**
  - Xbox (One, Series X/S)
  - PlayStation 5
  - Nintendo Switch
- **Desktop Platforms:**
  - Windows
  - macOS
  - Linux

Future support planned:

- Mobile platforms (iOS, Android)

## Telemetry

This toolkit supports optional operational telemetry using [Sentry](https://sentry.io) to improve reliability and diagnose issues. When enabled, telemetry helps identify test infrastructure failures, device connection problems, and automation bottlenecks.

### What's Collected

Examples of the types of telemetry data collected:

- Module errors and exceptions with context (platform, session ID, error category)
- Device connection failures and lock acquisition issues
- Test infrastructure problems (missing event captures, polling timeouts)
- Diagnostic operation breadcrumbs showing the sequence of operations leading to failures
- Performance metrics for critical operations (device connections, app deployments)

### Privacy & Control

**Telemetry is opt-in and requires explicit configuration:**

Telemetry is disabled by default. To enable it, set one of the following environment variables with your Sentry DSN:

**To enable telemetry for app-runner:**
```powershell
$env:SENTRY_APP_RUNNER_DSN = 'https://your-key@o123.ingest.sentry.io/your-project'
```

**To enable telemetry for sentry-api-client:**
```powershell
$env:SENTRY_API_CLIENT_DSN = 'https://your-key@o123.ingest.sentry.io/your-project'
```

**Note:** You can use the same DSN for both.

### Dependencies

The `Sentry` PowerShell module (v0.4.0) is bundled in the `vendor/Sentry` directory, so no installation is required. Telemetry will work automatically when a DSN is configured via environment variable.

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
