import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct MermaidDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        // .mmd is not a system-known type; register a dynamic one
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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        return WKWebView(frame: .zero, configuration: config)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(source: source, theme: theme)
        webView.loadHTMLString(html, baseURL: nil)
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
        body { margin: 0; padding: 20px; display: flex; justify-content: center; align-items: center; min-height: 100vh; background: \(theme == "dark" ? "#1e1e1e" : "#fff"); }
        #diagram { display: flex; justify-content: center; align-items: center; }
        #diagram svg { max-width: 100%; height: auto; }
        #error { color: #d33; font-family: monospace; white-space: pre-wrap; max-width: 800px; }
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
    @State private var exportFormat: String = "SVG"
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("default")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Toggle("Show Source", isOn: $showSource)
                    .toggleStyle(.checkbox)

                Spacer()

                Picker("Export", selection: $exportFormat) {
                    Text("SVG").tag("SVG")
                    Text("PNG").tag("PNG")
                    Text("PDF").tag("PDF")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Button("Export") {
                    exportDiagram()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Main content
            if showSource {
                HSplitView {
                    ScrollView {
                        TextEditor(text: $document.text)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(minWidth: 300, minHeight: 400)
                    }
                    MermaidWebView(source: document.text, theme: theme)
                        .frame(minWidth: 400, minHeight: 400)
                }
            } else {
                MermaidWebView(source: document.text, theme: theme)
            }

            if let err = exportError {
                Text(err)
                    .foregroundColor(.red)
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
        panel.allowedContentTypes = exportFormat == "SVG" ? [UTType.svg] :
            exportFormat == "PNG" ? [UTType.png] : [UTType.pdf]
        panel.nameFieldStringValue = "diagram.\(exportFormat.lowercased())"

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

