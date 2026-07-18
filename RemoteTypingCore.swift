import Foundation

func normalizedTextForSystemEventsTyping(_ text: String) -> String {
    var normalized = text
    for nonBreakingSpace in ["\u{00A0}", "\u{202F}", "\u{2007}"] {
        normalized = normalized.replacingOccurrences(of: nonBreakingSpace, with: " ")
    }
    return normalized
}

let systemEventsTypingScript = """
on run argv
    set fulltext to item 1 of argv

    tell application "System Events"
        repeat with i from 1 to length of fulltext
            keystroke (character i of fulltext)
            delay 0.01
        end repeat
    end tell
end run
"""
