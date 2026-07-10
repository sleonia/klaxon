import AppKit
import KlaxonKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Belt and braces with LSUIElement: menu-bar-only, no Dock icon.
app.setActivationPolicy(.accessory)
app.run()
