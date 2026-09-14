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
    let theme: String
    let zoomLevel: Double
    let fitMode: Bool  // true = auto-fit, false = manual zoom

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        loadHTML(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload HTML if source or theme changed
        if context.coordinator.lastSource != source || context.coordinator.lastTheme != theme {
            context.coordinator.lastSource = source
            context.coordinator.lastTheme = theme
            loadHTML(webView: webView)
        } else {
            // Just apply zoom without reloading
            applyZoom(webView: webView, coordinator: context.coordinator)
        }
    }

    private func loadHTML(webView: WKWebView) {
        let escaped = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 0; background: \(theme == "dark" ? "#1e1e1e" : "#fff"); }
        #diagram { display: flex; justify-content: center; align-items: flex-start; padding: 0; }
        #diagram svg { max-width: none; height: auto; }
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
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func applyZoom(webView: WKWebView, coordinator: Coordinator) {
        if fitMode {
            // Auto-fit: calculate zoom from actual SVG size vs webView size
            let js = """
            (function() {
                var svg = document.querySelector('#diagram svg');
                if (!svg) return '0,0';
                var rect = svg.getBoundingClientRect();
                return rect.width + ',' + rect.height;
            })();
            """
            webView.evaluateJavaScript(js) { result, _ in
                guard let str = result as? String, str != "0,0" else { return }
                let parts = str.split(separator: ",")
                guard parts.count == 2,
                      let svgW = Double(parts[0]),
                      let svgH = Double(parts[1]),
                      svgW > 0, svgH > 0 else { return }

                let viewW = webView.bounds.width
                let viewH = webView.bounds.height
                if viewW <= 0 || viewH <= 0 { return }

                let scaleX = viewW / svgW
                let scaleY = viewH / svgH
                let fitZoom = min(scaleX, scaleY) * 0.95  // 5% padding

                DispatchQueue.main.async {
                    webView.magnification = max(0.1, fitZoom)
                }
            }
        } else {
            webView.magnification = zoomLevel
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastSource: String = ""
        var lastTheme: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait for Mermaid to render the SVG
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkRendered(webView: webView)
            }
        }

        private func checkRendered(webView: WKWebView) {
            webView.evaluateJavaScript("document.querySelector('#diagram svg') !== null") { result, _ in
                if let rendered = result as? Bool, rendered {
                    // SVG is ready, notify SwiftUI to apply zoom
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: NSNotification.Name("MermaidRendered"), object: nil)
                    }
                } else {
                    // Not yet rendered, retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.checkRendered(webView: webView)
                    }
                }
            }
        }
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
    @State private var fitMode: Bool = true
    @State private var renderToken: Int = 0  // bumps to trigger re-evaluation after render

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
                    fitMode = true
                    renderToken += 1  // trigger re-eval
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .help("Auto-fit to window")

                Button {
                    fitMode = false
                    zoomLevel = max(0.25, zoomLevel - 0.1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .help("Zoom out")

                Text(fitMode ? "Fit" : "\(Int(zoomLevel * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 50)

                Button {
                    fitMode = false
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

            // Main content
            if showSource {
                HSplitView {
                    ScrollView {
                        TextEditor(text: $document.text)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(minWidth: 300, minHeight: 400)
                    }
                    MermaidWebView(
                        source: document.text,
                        theme: theme,
                        zoomLevel: zoomLevel,
                        fitMode: fitMode
                    )
                    .id(renderToken)  // force update when renderToken changes
                    .frame(minWidth: 400, minHeight: 400)
                }
            } else {
                MermaidWebView(
                    source: document.text,
                    theme: theme,
                    zoomLevel: zoomLevel,
                    fitMode: fitMode
                )
                .id(renderToken)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MermaidRendered"))) { _ in
            // Mermaid finished rendering SVG, bump token to trigger auto-fit
            renderToken += 1
        }
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