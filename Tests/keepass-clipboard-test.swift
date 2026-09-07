import AppKit

@MainActor
enum Paster {
    static func postCommandV(toPid: pid_t) { preconditionFailure("Clipboard tests must never synthesize keys") }
}

@main
struct KeePassClipboardTests {
    @MainActor
    static func main() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = KeePassClipboard(pasteboard: pasteboard)
        clipboard.write("fixture secret")
        precondition(pasteboard.string(forType: .string) == "fixture secret")
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.apple.is-sensitive"] {
            precondition(pasteboard.types?.contains(.init(marker)) == true)
        }
        clipboard.clear()
        precondition(pasteboard.string(forType: .string) == nil)
        clipboard.write("second secret")
        pasteboard.clearContents()
        pasteboard.setString("new clipboard content", forType: .string)
        clipboard.clear()
        precondition(pasteboard.string(forType: .string) == "new clipboard content")
        print("KeePass clipboard: sensitive markers, clearing, and preservation of later writes passed")
    }
}
