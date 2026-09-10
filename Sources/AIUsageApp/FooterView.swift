import SwiftUI
import ServiceManagement
import AppKit
import AIUsageCore

struct FooterView: View {
    var store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                TimelineView(.everyMinute) { _ in
                    if let date = store.lastQuotaRefresh {
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    } else { Text("Waiting for quota") }
                }.font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { store.refreshNow() }.disabled(store.isRefreshing).accessibilityLabel("Refresh usage")
            }
            HStack(spacing: 8) {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { value in setLaunchAtLogin(value) })).toggleStyle(.checkbox)
                Spacer(minLength: 0)
                Button("Rebuild index") { store.rebuildIndex() }.disabled(store.indexProgress.isRunning).accessibilityLabel("Rebuild history index")
                Button("Quit") { store.stop(); NSApplication.shared.terminate(nil) }.keyboardShortcut("q").accessibilityLabel("Quit AIUsage")
            }
            if let loginMessage { Text(loginMessage).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .font(.system(size: 10))
        .buttonStyle(.link)
        .onAppear { updateLoginStatus() }
    }
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            updateLoginStatus()
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginMessage = "Could not change launch at login. Install AIUsage in Applications and try again."
        }
    }
    private func updateLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        loginMessage = status == .requiresApproval ? "Allow AIUsage in System Settings → General → Login Items." : nil
    }
}
