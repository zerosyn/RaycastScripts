import AppKit
import ApplicationServices
import Foundation

private let targetBundleIdentifiers = [
    "com.microsoft.rdc.macos",
    "com.microsoft.rdc.mac",
    "com.microsoft.WindowsApp",
    "com.microsoft.windowsapp",
]

private let targetApplicationNames = [
    "Microsoft Remote Desktop",
    "Windows App",
]

private let activationDelay: useconds_t = 250_000

@main
struct PasteToRemoteDesktop {
    static func main() {
        guard AXIsProcessTrusted() else {
            print("Accessibility permission is required for Raycast")
            exit(1)
        }

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            print("Clipboard does not contain text")
            exit(1)
        }

        guard let remoteDesktopApp = findRemoteDesktopApp() else {
            print("Microsoft Remote Desktop or Windows App is not running")
            exit(1)
        }

        remoteDesktopApp.activate(options: [.activateAllWindows])
        usleep(activationDelay)

        do {
            try typeTextWithSystemEvents(normalizedTextForSystemEventsTyping(text))
        } catch {
            print("Failed to type clipboard text: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func findRemoteDesktopApp() -> NSRunningApplication? {
        for bundleIdentifier in targetBundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first {
                return app
            }
        }

        return NSWorkspace.shared.runningApplications.first { app in
            guard let localizedName = app.localizedName else { return false }
            return targetApplicationNames.contains(localizedName)
        }
    }

    private static func typeTextWithSystemEvents(_ text: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", systemEventsTypingScript, text]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "osascript exited with status \(process.terminationStatus)"
            throw NSError(
                domain: "PasteToRemoteDesktop",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorText.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }
}
