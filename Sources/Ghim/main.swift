import AppKit

// `Ghim --mcp`: run as a Model Context Protocol server on stdio (no UI).
if CommandLine.arguments.contains("--mcp") {
    MCPServer.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
