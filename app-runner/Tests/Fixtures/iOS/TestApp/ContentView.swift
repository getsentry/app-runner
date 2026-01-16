//
//  ContentView.swift
//  TestApp
//
//  Created by Serhii Snitsaruk on 08/01/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Text("SentryTestApp")
                .font(.title)
                .fontWeight(.bold)

            Text("Auto-closing in 3 seconds...")
                .font(.headline)
                .foregroundColor(.orange)

            if appState.launchArguments.isEmpty {
                Text("No launch arguments received")
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Launch Arguments (\(appState.launchArguments.count)):")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(appState.launchArguments.enumerated()), id: \.offset) {
                                index, arg in
                                Text("\(index + 1). \(arg)")
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
