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
    set targetAppNames to {"Microsoft Remote Desktop", "Windows App"}

    tell application id "com.apple.systemevents" to launch
    delay 0.2

    tell application id "com.apple.systemevents"
        set targetProcess to missing value
        repeat with targetAppName in targetAppNames
            if exists application process (targetAppName as text) then
                set targetProcess to application process (targetAppName as text)
                exit repeat
            end if
        end repeat

        if targetProcess is missing value then
            error "Microsoft Remote Desktop or Windows App is not running"
        end if

        set frontmost of targetProcess to true
        delay 0.25

        repeat with i from 1 to length of fulltext
            keystroke (character i of fulltext)
            delay 0.01
        end repeat
    end tell
end run
"""
