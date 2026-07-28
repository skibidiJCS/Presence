import AppKit
import SwiftUI

@main
struct PresenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = PresenceController.shared

    var body: some Scene {
        MenuBarExtra {
            PresenceMenuView(controller: controller)
        } label: {
            Image(systemName: controller.menuBarSymbol)
                .accessibilityLabel("Presence: \(controller.status.title)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PresenceController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PresenceController.shared.shutdown()
    }
}

