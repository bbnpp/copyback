import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // Dock 아이콘 없이 메뉴 막대에만 표시
    withExtendedLifetime(delegate) {
        app.run()
    }
}
