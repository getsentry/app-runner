//
//  TestAppApp.swift
//  TestApp
//
//  Created by Serhii Snitsaruk on 08/01/2026.
//

import Combine
import Foundation
import SwiftUI
import os.log

@main
struct TestAppApp: App {
    @StateObject private var appState = AppState()

    // Shared logger for consistent logging throughout the app
    private static let logger = OSLog(
        subsystem: "io.sentry.apprunner.TestApp", category: "SentryTestApp")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }

    init() {
        createTestFiles()
        processLaunchArguments()
        startAutoCloseTimer()
    }

    private func processLaunchArguments() {
        let arguments = CommandLine.arguments
        os_log("Application started", log: Self.logger, type: .info)

        // Skip the first argument (app name)
        let launchArgs = Array(arguments.dropFirst())

        if launchArgs.isEmpty {
            os_log("No launch arguments received", log: Self.logger, type: .info)
        } else {
            os_log(
                "Received %d launch argument(s):", log: Self.logger, type: .info, launchArgs.count)

            // Process arguments in pairs (--key value) or individually
            var i = 0
            while i < launchArgs.count {
                let arg = launchArgs[i]

                if arg.starts(with: "--") && i + 1 < launchArgs.count {
                    // Key-value pair
                    let key = arg
                    let value = launchArgs[i + 1]
                    os_log("  %@ = %@", log: Self.logger, type: .info, key, value)
                    i += 2
                } else {
                    // Single argument
                    os_log("  %@", log: Self.logger, type: .info, arg)
                    i += 1
                }
            }
        }
    }

    private func startAutoCloseTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            os_log("Auto-closing application", log: Self.logger, type: .info)
            self.terminateApp()
        }
    }

    private func terminateApp() {
        os_log("Application terminated", log: Self.logger, type: .info)
        exit(0)
    }

    private func createTestFiles() {
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

            // Create test file for CopyDeviceItem and LogFilePath testing
            let testFileURL = documentsURL.appendingPathComponent("test-file.txt")
            try "Test file content".write(to: testFileURL, atomically: true, encoding: .utf8)
        } catch {
            os_log(
                "Failed to create test file: %@", log: Self.logger, type: .error,
                error.localizedDescription)
        }
    }

}

class AppState: ObservableObject {
    @Published var launchArguments: [String] = []

    init() {
        launchArguments = Array(CommandLine.arguments.dropFirst())
    }
}
