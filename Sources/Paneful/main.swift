import AppKit

// Create the application before the delegate, which reads NSScreen during init.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
