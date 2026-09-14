import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct MermaidDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(importedAs: "com.mermaid.mmd")]
    }
    static var writableContentTypes: [UTType] {
        [UTType(importedAs: "com.mermaid.mmd")]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - Mermaid WebView

struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: String  // "default" or "dark"
    @Binding var zoomLevel: Double

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(source: source, theme: theme)
        webView.loadHTMLString(html, baseURL: nil)
        // Apply zoom via WKWebView's native magnification
        DispatchQueue.main.async {
            webView.magnification = zoomLevel
        }
    }

    private func buildHTML(source: String, theme: String) -> String {
        let escaped = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 20px; display: flex; justify-content: center; align-items: flex-start; min-height: 100vh; background: \(theme == "dark" ? "#1e1e1e" : "#fff"); }
        #diagram { display: flex; justify-content: center; align-items: center; }
        #diagram svg { max-width: 100%; height: auto; }
        #error { color: #d33; font-family: monospace; white-space: pre-wrap; max-width: 800px; padding: 20px; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
        </head>
        <body>
        <div id="diagram">
        <pre class="mermaid">\(escaped)</pre>
        </div>
        <div id="error"></div>
        <script>
        try {
            mermaid.initialize({ startOnLoad: true, theme: '\(theme)' });
        } catch (err) {
            document.getElementById('error').textContent = String(err);
        }
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - Main View

struct ContentView: View {
    @Binding var document: MermaidDocument
    @State private var theme: String = "default"
    @State private var showSource: Bool = false
    @State private var exportFormat: String = "svg"
    @State private var exportError: String?
    @State private var zoomLevel: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Theme
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("default")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()

                // Show Source
                Button {
                    showSource.toggle()
                } label: {
                    Label("Source", systemImage: "curlybraces")
                }
                .buttonStyle(.bordered)
                .help("Toggle source editor")

                Divider()
                    .frame(height: 20)

                // Zoom controls
                Button {
                    zoomLevel = 1.0
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .help("Reset zoom")

                Button {
                    zoomLevel = max(0.25, zoomLevel - 0.1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .help("Zoom out")

                Text("\(Int(zoomLevel * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 44)

                Button {
                    zoomLevel = min(5.0, zoomLevel + 0.1)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .help("Zoom in")

                Spacer()

                // Export
                Button {
                    exportDiagram()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Export diagram")

                Picker("", selection: $exportFormat) {
                    Text("SVG").tag("svg")
                    Text("PNG").tag("png")
                    Text("PDF").tag("pdf")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main content — let WKWebView handle its own scrolling
            if showSource {
                HSplitView {
                    ScrollView {
                        TextEditor(text: $document.text)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(minWidth: 300, minHeight: 400)
                    }
                    MermaidWebView(source: document.text, theme: theme, zoomLevel: $zoomLevel)
                        .frame(minWidth: 400, minHeight: 400)
                }
            } else {
                MermaidWebView(source: document.text, theme: theme, zoomLevel: $zoomLevel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let err = exportError {
                Text(err)
                    .foregroundColor(err.hasPrefix("Exported") ? .secondary : .red)
                    .font(.caption)
                    .padding(4)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Export

    private func exportDiagram() {
        guard !document.text.isEmpty else {
            exportError = "Nothing to export"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = exportFormat == "svg" ? [UTType.svg] :
            exportFormat == "png" ? [UTType.png] : [UTType.pdf]
        panel.nameFieldStringValue = "diagram.\(exportFormat)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let tempMmd = FileManager.default.temporaryDirectory.appendingPathComponent("export.mmd")
        do {
            try document.text.data(using: .utf8)!.write(to: tempMmd)

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = [
                "npx", "-p", "@mermaid-js/mermaid-cli", "mmdc",
                "-i", tempMmd.path,
                "-o", url.path,
                "-t", theme == "dark" ? "dark" : "default"
            ]

            let pipe = Pipe()
            task.standardError = pipe
            task.standardOutput = pipe

            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                exportError = "Exported to \(url.lastPathComponent)"
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                exportError = "Export failed: \(String(data: data, encoding: .utf8) ?? "unknown error")"
            }
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}