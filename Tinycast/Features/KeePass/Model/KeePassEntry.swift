import Foundation

struct KeePassEntry: Identifiable, Sendable, Equatable {
    let id: String
    let group: String
    let title: String
    let username: String
    let password: String
    let url: String
    let notes: String
    let totp: String

    enum Field: String, CaseIterable {
        case password = "Password"
        case username = "Username"
        case totp = "One-Time Code"
        case url = "URL"
    }

    func value(_ field: Field, at date: Date) throws -> String {
        let raw: String
        switch field {
        case .password: raw = password
        case .username: raw = username
        case .url: raw = url
        case .totp: return try KeePassTOTP.generate(totp, at: date)
        }
        let substitutions = [
            "TITLE": title, "USERNAME": username, "PASSWORD": password, "URL": url, "NOTES": notes
        ]
        var result = raw
        for (key, value) in substitutions.sorted(by: { $0.key < $1.key }) {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        if result.contains("{TOTP}") {
            result = try result.replacingOccurrences(of: "{TOTP}", with: KeePassTOTP.generate(totp, at: date))
        }
        return result
    }

    func matches(_ query: String, folder: String) -> Bool {
        guard folder.isEmpty || group == folder || group.hasPrefix(folder + "/") else { return false }
        let text = [title, username, url, group].joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            text.localizedStandardContains(String($0))
        }
    }
}
