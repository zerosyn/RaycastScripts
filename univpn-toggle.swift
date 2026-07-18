#!/usr/bin/swift

import AppKit
import ApplicationServices

private let bundleIdentifier = ProcessInfo.processInfo.environment["UNIVPN_BUNDLE_ID"] ?? "work.VPNClient"
private let routeIP = ProcessInfo.processInfo.environment["UNIVPN_ROUTE_IP"] ?? "192.168.11.254"
private let menuRetryTimeout: TimeInterval = 8
private let stateChangeTimeout: TimeInterval = 15

private enum VPNState: String {
    case connected = "已连接"
    case disconnected = "未连接"

    var opposite: VPNState { self == .connected ? .disconnected : .connected }
    var actionName: String { self == .connected ? "断开" : "连接" }
    var menuPrefixes: [String] {
        self == .connected
            ? ["断开连接", "断开", "Disconnect"]
            : ["连接", "Connect"]
    }
}

private func commandOutput(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return nil
    }

    guard process.terminationStatus == 0 else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

private func currentState() -> VPNState? {
    guard let table = commandOutput("/usr/sbin/netstat", ["-rn"]) else {
        return nil
    }

    let hasHostRoute = table.split(separator: "\n").contains { line in
        guard let destination = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else {
            return false
        }
        return destination == Substring(routeIP) || destination == Substring("\(routeIP)/32")
    }
    return hasHostRoute ? .connected : .disconnected
}

private func waitForState(_ expected: VPNState, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if currentState() == expected { return true }
        Thread.sleep(forTimeInterval: 0.4)
    } while Date() < deadline
    return currentState() == expected
}

private func alertIcon(for state: VPNState) -> NSImage? {
    let symbolName = state == .connected ? "checkmark.shield.fill" : "xmark.shield.fill"
    let color = state == .connected ? NSColor.systemGreen : NSColor.systemRed

    if let symbol = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: "VPN \(state.rawValue)"
    ) {
        return symbol.withSymbolConfiguration(.init(paletteColors: [color]))
    }

    let fallbackName = state == .connected ? NSImage.statusAvailableName : NSImage.statusUnavailableName
    return NSImage(named: fallbackName)
}

private func confirmAction(for state: VPNState) -> Bool {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "UniVPN"
    alert.informativeText = "当前 UniVPN 状态：\(state.rawValue)。是否执行\(state.actionName)？"
    alert.alertStyle = .informational
    alert.icon = alertIcon(for: state)
    alert.addButton(withTitle: state.actionName)
    let cancelButton = alert.addButton(withTitle: "取消")
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.keyEquivalentModifierMask = []
    return alert.runModal() == .alertFirstButtonReturn
}

private func runningVPNApplication() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
}

private func startVPNApplication() -> NSRunningApplication? {
    if let running = runningVPNApplication() { return running }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", bundleIdentifier]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    let deadline = Date().addingTimeInterval(8)
    repeat {
        if let running = runningVPNApplication() { return running }
        Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    return runningVPNApplication()
}

private func attribute<T>(_ name: CFString, of element: AXUIElement) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value as? T
}

private func role(of element: AXUIElement) -> String {
    attribute(kAXRoleAttribute as CFString, of: element) ?? ""
}

private func title(of element: AXUIElement) -> String {
    let value: String? = attribute(kAXTitleAttribute as CFString, of: element)
    return value ?? ""
}

private func descendants(
    of element: AXUIElement,
    matchingRole wantedRole: String,
    depth: Int = 0,
    maxDepth: Int = 8
) -> [AXUIElement] {
    guard depth <= maxDepth else { return [] }

    var matches: [AXUIElement] = []
    if role(of: element) == wantedRole { matches.append(element) }

    let children: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, of: element) ?? []
    for child in children {
        matches.append(contentsOf: descendants(
            of: child,
            matchingRole: wantedRole,
            depth: depth + 1,
            maxDepth: maxDepth
        ))
    }
    return matches
}

private func menuBars(of application: AXUIElement) -> [AXUIElement] {
    let names = [kAXExtrasMenuBarAttribute as CFString, kAXMenuBarAttribute as CFString]
    return names.compactMap { name in
        let bar: AXUIElement? = attribute(name, of: application)
        return bar
    }
}

private func matchingMenuItem(in roots: [AXUIElement], prefixes: [String]) -> AXUIElement? {
    let items = roots.flatMap {
        descendants(of: $0, matchingRole: kAXMenuItemRole as String, maxDepth: 8)
    }

    return items.first { item in
        let itemTitle = title(of: item).trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled: Bool = attribute(kAXEnabledAttribute as CFString, of: item) ?? true
        return enabled && prefixes.contains(where: { itemTitle.hasPrefix($0) })
    }
}

private func openMenu(_ item: AXUIElement) -> AXError {
    let showResult = AXUIElementPerformAction(item, kAXShowMenuAction as CFString)
    if showResult == .success { return showResult }
    return AXUIElementPerformAction(item, kAXPressAction as CFString)
}

private func clickVPNMenuItem(
    application: AXUIElement,
    targetPrefixes: [String]
) -> String? {
    let deadline = Date().addingTimeInterval(menuRetryTimeout)

    repeat {
        let bars = menuBars(of: application)
        let statusItems = bars.flatMap {
            descendants(of: $0, matchingRole: kAXMenuBarItemRole as String, maxDepth: 3)
        }

        for statusItem in statusItems {
            guard openMenu(statusItem) == .success else { continue }
            Thread.sleep(forTimeInterval: 0.25)

            if let target = matchingMenuItem(in: [statusItem] + bars, prefixes: targetPrefixes) {
                let itemTitle = title(of: target)
                if AXUIElementPerformAction(target, kAXPressAction as CFString) == .success {
                    return itemTitle
                }
            }

            _ = AXUIElementPerformAction(statusItem, kAXPressAction as CFString)
        }

        Thread.sleep(forTimeInterval: 0.4)
    } while Date() < deadline

    return nil
}

private func postReturn(to processIdentifier: pid_t) {
    guard let source = CGEventSource(stateID: .hidSystemState),
          let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
        return
    }
    keyDown.postToPid(processIdentifier)
    keyUp.postToPid(processIdentifier)
}

private func finishConnectionIfNeeded(processIdentifier: pid_t) -> Bool {
    if waitForState(.connected, timeout: 2) { return true }

    // UniVPN's Qt certificate warning is not always present in the accessibility tree.
    // Send Return only to UniVPN's process, never to the globally focused application.
    postReturn(to: processIdentifier)
    if waitForState(.connected, timeout: 2) { return true }
    postReturn(to: processIdentifier)
    return waitForState(.connected, timeout: stateChangeTimeout)
}

guard let initialState = currentState() else {
    print("无法读取系统路由表，未执行任何操作")
    exit(1)
}
guard confirmAction(for: initialState) else {
    print("当前状态：\(initialState.rawValue)；已取消")
    exit(0)
}

guard currentState() == initialState else {
    print("UniVPN 状态在确认期间发生变化，请重试")
    exit(1)
}

guard AXIsProcessTrusted() else {
    print("Raycast 需要辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能")
    exit(1)
}

guard let vpnApplication = startVPNApplication() else {
    print("无法启动 UniVPN（bundle id: \(bundleIdentifier)）")
    exit(1)
}

let appElement = AXUIElementCreateApplication(vpnApplication.processIdentifier)
guard let clickedItem = clickVPNMenuItem(
    application: appElement,
    targetPrefixes: initialState.menuPrefixes
) else {
    print("没有找到可用的“\(initialState.actionName)”菜单项；UniVPN 可能正在重连")
    exit(1)
}

let changed: Bool
if initialState == .disconnected {
    changed = finishConnectionIfNeeded(processIdentifier: vpnApplication.processIdentifier)
} else {
    changed = waitForState(.disconnected, timeout: stateChangeTimeout)
}

guard changed else {
    print("已点击“\(clickedItem)”，但 VPN 状态未在 \(Int(stateChangeTimeout)) 秒内改变")
    exit(1)
}

print("UniVPN \(initialState.actionName)成功；当前状态：\(initialState.opposite.rawValue)")
