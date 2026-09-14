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

// MARK: - Box Zoom Overlay

class BoxZoomOverlayView: NSView {
    var onBoxZoom: ((NSRect) -> Void)?
    var boxZoomMode: Bool = false {
        didSet {
            needsDisplay = true
            // Change cursor
            if boxZoomMode {
                NSCursor.crosshair.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }

    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    override var isFlipped: Bool { false }

    // When box-zoom mode is off, pass all mouse events through to the WKWebView below
    override func hitTest(_ point: NSPoint) -> NSView? {
        return boxZoomMode ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard boxZoomMode else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPoint!, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard boxZoomMode, let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard boxZoomMode else { return }
        guard let rect = currentRect, rect.width > 5, rect.height > 5 else {
            currentRect = nil
            needsDisplay = true
            return
        }
        onBoxZoom?(rect)
        currentRect = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard boxZoomMode, let rect = currentRect else { return }
        // Semi-transparent fill
        NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 0.15).setFill()
        rect.fill()
        // Border
        NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 0.9).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }
}

// MARK: - Mermaid WebView

struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: String
    let zoomLevel: Double
    let fitMode: Bool
    @Binding var boxZoomMode: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        // Create webview
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        // Create overlay for box-zoom
        let overlay = BoxZoomOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        container.addSubview(overlay)

        // Pin both to container edges
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.webView = webView
        context.coordinator.lastSource = source
        context.coordinator.lastTheme = theme

        // Box zoom callback
        overlay.onBoxZoom = { [weak webView] rect in
            guard let webView = webView else { return }
            guard rect.width > 10, rect.height > 10 else { return }

            let viewW = webView.bounds.width
            let viewH = webView.bounds.height
            guard viewW > 0, viewH > 0 else { return }

            // Current magnification
            let currentZoom = webView.magnification

            // How much more do we need to zoom to fit the selected rect into the full view?
            let scaleX = viewW / rect.width
            let scaleY = viewH / rect.height
            let zoomFactor = min(scaleX, scaleY)
            let newZoom = max(0.1, min(5.0, currentZoom * zoomFactor))

            // Center point in webView coords (overlay and webview share same frame)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            webView.setMagnification(newZoom, centeredAt: center)
        }

        loadHTML(webView: webView)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let webView = context.coordinator.webView else { return }

        // Find overlay subview
        let overlay = container.subviews.compactMap({ $0 as? BoxZoomOverlayView }).first
        overlay?.boxZoomMode = boxZoomMode

        let sourceChanged = context.coordinator.lastSource != source
        let themeChanged = context.coordinator.lastTheme != theme

        if sourceChanged || themeChanged {
            context.coordinator.lastSource = source
            context.coordinator.lastTheme = theme
            context.coordinator.pendingFit = fitMode
            loadHTML(webView: webView)
            return
        }

        // Apply zoom centered on view center (not top-left)
        let center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        if fitMode {
            context.coordinator.applyAutoFit(webView: webView)
        } else {
            webView.setMagnification(zoomLevel, centeredAt: center)
        }
    }

    private func loadHTML(webView: WKWebView) {
        let escaped = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let bg = theme == "dark" ? "#1e1e1e" : "#fff"
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 0; background: \(bg); }
        #diagram { display: flex; justify-content: center; align-items: flex-start; }
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

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastSource: String = ""
        var lastTheme: String = ""
        var pendingFit: Bool = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            waitForRender(webView: webView, attempts: 0)
        }

        private func waitForRender(webView: WKWebView, attempts: Int) {
            if attempts > 50 { return }
            webView.evaluateJavaScript("document.querySelector('#diagram svg') !== null") { result, _ in
                if let ready = result as? Bool, ready {
                    if self.pendingFit {
                        self.applyAutoFit(webView: webView)
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.waitForRender(webView: webView, attempts: attempts + 1)
                    }
                }
            }
        }

        func applyAutoFit(webView: WKWebView) {
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
                let fitZoom = min(scaleX, scaleY) * 0.95

                let center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
                DispatchQueue.main.async {
                    webView.setMagnification(max(0.1, fitZoom), centeredAt: center)
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
    @State private var boxZoomMode: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("default")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .labelsHidden()

                Button {
                    showSource.toggle()
                } label: {
                    Label("Source", systemImage: "curlybraces")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 20)

                // Auto-fit
                Button {
                    fitMode = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .help("Auto-fit to window")

                // Zoom out
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

                // Zoom in
                Button {
                    fitMode = false
                    zoomLevel = min(5.0, zoomLevel + 0.1)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .help("Zoom in")

                // Box zoom toggle
                Button {
                    boxZoomMode.toggle()
                } label: {
                    Image(systemName: "rectangle.dashed.and.paperclip")
                        .foregroundStyle(boxZoomMode ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.bordered)
                .help("Box zoom: draw a rectangle to zoom into that area")

                Spacer()

                // Export
                Button {
                    exportDiagram()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

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
                        fitMode: fitMode,
                        boxZoomMode: $boxZoomMode
                    )
                    .frame(minWidth: 400, minHeight: 400)
                }
            } else {
                MermaidWebView(
                    source: document.text,
                    theme: theme,
                    zoomLevel: zoomLevel,
                    fitMode: fitMode,
                    boxZoomMode: $boxZoomMode
                )
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