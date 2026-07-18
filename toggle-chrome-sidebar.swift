#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title Toggle Chrome Sidebar
// @raycast.mode silent

// Optional parameters:
// @raycast.icon 📑
// @raycast.packageName Chrome Utils

import AppKit
import ApplicationServices

let targetTitles = [
    "Expand tabs",
    "Collapse tabs",
    "展开标签页",
    "收起标签页",
    "折叠标签页",
]

let maxSearchDepth = 25

guard let chromeApp = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.google.Chrome"
).first else {
    print("Chrome is not running")
    exit(1)
}

let appElement = AXUIElementCreateApplication(chromeApp.processIdentifier)

var windowsValue: CFTypeRef?
guard AXUIElementCopyAttributeValue(
    appElement,
    kAXWindowsAttribute as CFString,
    &windowsValue
) == .success,
let windows = windowsValue as? [AXUIElement],
!windows.isEmpty else {
    print("No Chrome windows found")
    exit(1)
}

func findButton(element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > maxSearchDepth { return nil }

    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

    var desc: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)

    let roleStr = role as? String ?? ""
    let titleStr = title as? String ?? ""
    let descStr = desc as? String ?? ""

    if roleStr == (kAXButtonRole as String)
        && (targetTitles.contains(titleStr) || targetTitles.contains(descStr)) {
        return element
    }

    var children: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

    guard let childArray = children as? [AXUIElement] else { return nil }

    for child in childArray {
        if let found = findButton(element: child, depth: depth + 1) {
            return found
        }
    }
    return nil
}

let button = windows.lazy.compactMap { findButton(element: $0) }.first

guard let button else {
    print("Sidebar toggle button not found in accessibility tree")
    exit(1)
}

let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
if result != .success {
    print("Failed to press sidebar toggle button: \(result.rawValue)")
    exit(1)
}
