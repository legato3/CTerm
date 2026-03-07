import Foundation

@MainActor
class BrowserTabController {
    var browserState: BrowserState?

    init(url: URL) {
        self.browserState = BrowserState(url: url)
    }

    func deactivate() {
        browserState = nil
    }
}
