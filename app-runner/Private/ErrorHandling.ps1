# Standardized Error Handling Framework
# Provides consistent error handling patterns across the module

# Error Categories
enum ConsoleErrorCategory {
    SessionManagement
    PlatformConnection
    ConsoleLifecycle
    ApplicationManagement
    Diagnostics
    Configuration
    NetworkTimeout
    Authentication
    Validation
    Unknown
}

# Custom Exception Classes
class ConsoleException : System.Exception {
    [ConsoleErrorCategory]$Category
    [string]$Platform
    [string]$SessionId
    [hashtable]$Context

    ConsoleException([string]$message) : base($message) {
        $this.Category = [ConsoleErrorCategory]::Unknown
        $this.Context = @{}
    }

    ConsoleException([string]$message, [ConsoleErrorCategory]$category) : base($message) {
        $this.Category = $category
        $this.Context = @{}
    }

    ConsoleException([string]$message, [ConsoleErrorCategory]$category, [Exception]$innerException) : base($message, $innerException) {
        $this.Category = $category
        $this.Context = @{}
    }

    [string]GetDetailedMessage() {
        $details = @()
        $details += "Error: $($this.Message)"
        $details += "Category: $($this.Category)"

        if ($this.Platform) {
            $details += "Platform: $($this.Platform)"
        }

        if ($this.SessionId) {
            $details += "Session ID: $($this.SessionId)"
        }

        if ($this.Context.Count -gt 0) {
            $details += "Context:"
            foreach ($key in $this.Context.Keys) {
                $details += "  ${key}: $($this.Context[$key])"
            }
        }

        if ($this.InnerException) {
            $details += "Inner Exception: $($this.InnerException.Message)"
        }

        return $details -join "`n"
    }
}

class SessionException : ConsoleException {
    SessionException([string]$message) : base($message, [ConsoleErrorCategory]::SessionManagement) {}
    SessionException([string]$message, [Exception]$innerException) : base($message, [ConsoleErrorCategory]::SessionManagement, $innerException) {}
}

class PlatformException : ConsoleException {
    PlatformException([string]$message, [string]$platform) : base($message, [ConsoleErrorCategory]::PlatformConnection) {
        $this.Platform = $platform
    }
    PlatformException([string]$message, [string]$platform, [Exception]$innerException) : base($message, [ConsoleErrorCategory]::PlatformConnection, $innerException) {
        $this.Platform = $platform
    }
}

class ConsoleLifecycleException : ConsoleException {
    ConsoleLifecycleException([string]$message) : base($message, [ConsoleErrorCategory]::ConsoleLifecycle) {}
    ConsoleLifecycleException([string]$message, [Exception]$innerException) : base($message, [ConsoleErrorCategory]::ConsoleLifecycle, $innerException) {}
}

class ApplicationException : ConsoleException {
    ApplicationException([string]$message) : base($message, [ConsoleErrorCategory]::ApplicationManagement) {}
    ApplicationException([string]$message, [Exception]$innerException) : base($message, [ConsoleErrorCategory]::ApplicationManagement, $innerException) {}
}

class ConfigurationException : ConsoleException {
    ConfigurationException([string]$message) : base($message, [ConsoleErrorCategory]::Configuration) {}
    ConfigurationException([string]$message, [Exception]$innerException) : base($message, [ConsoleErrorCategory]::Configuration, $innerException) {}
}

# Error Handler Class
class ErrorHandler {
    static [hashtable]$ErrorLog = @{}
    static [int]$ErrorCount = 0

    static [void]LogError([ConsoleException]$exception) {
        $errorId = [Guid]::NewGuid().ToString()
        $timestamp = Get-Date

        [ErrorHandler]::ErrorLog[$errorId] = @{
            Timestamp      = $timestamp
            Exception      = $exception
            Category       = $exception.Category
            Platform       = $exception.Platform
            ConsoleId      = $exception.ConsoleId
            Message        = $exception.Message
            InnerException = $exception.InnerException
            Context        = $exception.Context
            StackTrace     = $exception.StackTrace
        }

        [ErrorHandler]::ErrorCount++

        # Log to PowerShell error stream
        Write-Error $exception.GetDetailedMessage() -ErrorId $errorId

        # Log to debug stream for troubleshooting
        Write-Debug "Error logged with ID: $errorId"

        # Send to Sentry for operational visibility
        if (Get-Command -Name TryOut-Sentry -ErrorAction SilentlyContinue) {
            $sentryTags = @{
                error_id = $errorId
                category = $exception.Category.ToString()
            }

            if ($exception.Platform) {
                $sentryTags['platform'] = $exception.Platform
            }

            if ($exception.SessionId) {
                $sentryTags['session_id'] = $exception.SessionId
            }

            # Add context as extra data in scope
            $message = $exception.GetDetailedMessage()
            if ($exception.Context.Count -gt 0) {
                TryEdit-SentryScope {
                    foreach ($key in $exception.Context.Keys) {
                        $_.SetExtra($key, $exception.Context[$key])
                    }
                }
            }

            TryOut-Sentry -InputObject $message -Tag $sentryTags -Level Error
        }
    }

    static [void]LogError([string]$message, [ConsoleErrorCategory]$category) {
        $exception = [ConsoleException]::new($message, $category)
        [ErrorHandler]::LogError($exception)
    }

    static [array]GetRecentErrors([int]$count = 10) {
        $sortedErrors = [ErrorHandler]::ErrorLog.Values | Sort-Object Timestamp -Descending
        return $sortedErrors | Select-Object -First $count
    }

    static [array]GetErrorsByCategory([ConsoleErrorCategory]$category) {
        return [ErrorHandler]::ErrorLog.Values | Where-Object { $_.Category -eq $category }
    }

    static [void]ClearErrorLog() {
        [ErrorHandler]::ErrorLog.Clear()
        [ErrorHandler]::ErrorCount = 0
    }

    static [int]GetErrorCount() {
        return [ErrorHandler]::ErrorCount
    }
}

# Essential Error Handling Functions