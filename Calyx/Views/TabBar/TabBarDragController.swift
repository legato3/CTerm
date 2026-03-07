import AppKit

enum TabBarDragController {
    static let pasteboardType = NSPasteboard.PasteboardType("com.calyx.tabID")

    static func writeToPasteboard(_ pasteboard: NSPasteboard, tabID: UUID) {
        pasteboard.declareTypes([pasteboardType], owner: nil)
        pasteboard.setString(tabID.uuidString, forType: pasteboardType)
    }

    static func readFromPasteboard(_ pasteboard: NSPasteboard) -> UUID? {
        guard let string = pasteboard.string(forType: pasteboardType) else { return nil }
        return UUID(uuidString: string)
    }

    @MainActor
    static func validateDrop(tabID: UUID, in group: TabGroup) -> Bool {
        group.tabs.contains { $0.id == tabID }
    }
}
