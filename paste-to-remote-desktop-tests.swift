import Foundation

@main
struct PasteToRemoteDesktopTests {
    static func main() {
        assertContains(
            systemEventsTypingScript,
            "on run argv",
            "accepts clipboard text as an osascript argument"
        )

        assertContains(
            systemEventsTypingScript,
            "keystroke (character i of fulltext)",
            "types through System Events one character at a time"
        )

        assertEqual(
            normalizedTextForSystemEventsTyping("AND\u{00A0}\u{00A0}la.create_time\u{00A0}BETWEEN\u{00A0}UNIX_TIMESTAMP('{start_day}')\u{00A0}*\u{00A0}1000"),
            "AND  la.create_time BETWEEN UNIX_TIMESTAMP('{start_day}') * 1000",
            "normalizes non-breaking spaces before System Events typing"
        )
    }

    private static func assertEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String
    ) {
        if actual != expected {
            fputs("FAILED: \(message)\nexpected: \(expected)\nactual: \(actual)\n", stderr)
            exit(1)
        }
    }

    private static func assertContains(
        _ actual: String,
        _ expected: String,
        _ message: String
    ) {
        if !actual.contains(expected) {
            fputs("FAILED: \(message)\nmissing: \(expected)\n", stderr)
            exit(1)
        }
    }
}
