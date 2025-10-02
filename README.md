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

## Requirements

### Platform-Specific Prerequisites

**Important:** Using this toolkit to run applications on game consoles requires:

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
