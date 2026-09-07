enum KeePassAutoLock {
    static let defaultSeconds = 300
    static let presets = [60, 300, 900, 3600]

    static func title(seconds: Int?) -> String {
        switch seconds {
        case 60: "1 minute"
        case 300: "5 minutes"
        case 900: "15 minutes"
        case 3600: "1 hour"
        default: "Never"
        }
    }
}
