import Foundation

enum KeePassCSV {
    enum Failure: LocalizedError {
        case invalid
        var errorDescription: String? { "KeePassXC returned an unreadable database export." }
    }

    static func entries(from data: Data) throws -> [KeePassEntry] {
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalid }
        let records = try parse(text)
        guard let header = records.first, header.prefix(3) == ["Group", "Title", "Username"],
            header.count >= 7
        else { throw Failure.invalid }
        var entries: [KeePassEntry] = []
        var occurrences: [String: Int] = [:]
        for row in records.dropFirst() {
            guard row.count >= 7 else { throw Failure.invalid }
            let groups = row[0].split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            let excluded = ["Deprecated", "Recycle Bin", "Trash", "回收站"]
            guard !row[1].isEmpty,
                !groups.contains(where: { group in excluded.contains { group.hasPrefix($0) } })
            else { continue }
            let identity = row.prefix(3).map { "\($0.utf8.count):\($0)" }.joined()
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            entries.append(KeePassEntry(
                id: "\(identity):\(occurrence)", group: groups.joined(separator: "/"),
                title: row[1], username: row[2], password: row[3], url: row[4], notes: row[5], totp: row[6]))
        }
        return entries.sorted {
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            return titleOrder == .orderedSame
                ? $0.username.localizedStandardCompare($1.username) == .orderedAscending
                : titleOrder == .orderedAscending
        }
    }

    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var cursor = text.startIndex
        if text.first == "\u{feff}" { cursor = text.index(after: cursor) }
        while cursor < text.endIndex {
            let character = text[cursor]
            let next = text.index(after: cursor)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        cursor = text.index(after: next)
                        continue
                    }
                    quoted = false
                    closedQuote = true
                } else { field.append(character) }
            } else if character == "," {
                row.append(field); field = ""; closedQuote = false
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                if row != [""] { rows.append(row) }
                row = []; field = ""; closedQuote = false
            } else if character == "\"", field.isEmpty, !closedQuote {
                quoted = true
            } else {
                guard !closedQuote, character != "\"" else { throw Failure.invalid }
                field.append(character)
            }
            cursor = next
        }
        guard !quoted else { throw Failure.invalid }
        if !row.isEmpty || !field.isEmpty || closedQuote { rows.append(row + [field]) }
        return rows
    }
}
