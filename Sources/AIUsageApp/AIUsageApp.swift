import AppKit
import SwiftUI
import AIUsageCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        // Finder can open a development copy, an installed copy, or a copy on a DMG.
        // Keep the oldest instance so only one status item and refresh loop survive.
        let first = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).min { lhs, rhs in
            let left = lhs.launchDate ?? .distantPast, right = rhs.launchDate ?? .distantPast
            return left == right ? lhs.processIdentifier < rhs.processIdentifier : left < right
        }
        if let first, first.processIdentifier != current.processIdentifier {
            first.activate()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            MenuBarLabel(store: store).task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
