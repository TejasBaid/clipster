import AppKit

let app = NSApplication.shared
let delegate = AppDelegate(previewMode: CommandLine.arguments.contains("--preview"))
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
