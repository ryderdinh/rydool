import AppKit

/// Entry point. Rydool is a menu bar (accessory) app, so it is driven by
/// AppKit directly rather than a SwiftUI `App` scene.
@main
enum RydoolBootstrap {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
