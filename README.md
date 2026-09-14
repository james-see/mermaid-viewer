# Mermaid Viewer

A native macOS app for opening, previewing, and exporting [Mermaid](https://mermaid.js.org/) diagrams (`.mmd` files).

## Features

- **Native macOS app** — built with SwiftUI, not Electron
- **Live preview** — renders Mermaid diagrams in-app using the Mermaid 11 engine via WebKit
- **Light/Dark themes** — toggle between default and dark Mermaid themes
- **Source editor** — split view to edit the `.mmd` source alongside the rendered diagram
- **Export** — convert diagrams to SVG, PNG, or PDF via `mmdc` (mermaid-cli)
- **Default app** — registers as the system default handler for `.mmd` files

## Installation

### Build from source

```bash
# Requires Xcode 15+ and macOS 14+
git clone https://github.com/james-see/mermaid-viewer.git
cd mermaid-viewer
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project MermaidViewer.xcodeproj -scheme MermaidViewer -configuration Release build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
cp -R ~/Library/Developer/Xcode/DerivedData/MermaidViewer-*/Build/Products/Release/MermaidViewer.app /Applications/
```

### Set as default for `.mmd` files

```bash
brew install duti
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/MermaidViewer.app
duti -s com.james-see.mermaidviewer .mmd all
```

### Prerequisites for export

The export feature uses `mmdc` (mermaid-cli):

```bash
npm install -g @mermaid-js/mermaid-cli
```

## CLI conversion

You can also convert `.mmd` files from the command line:

```bash
# SVG
mmdc -i diagram.mmd -o diagram.svg

# PNG
mmdc -i diagram.mmd -o diagram.png

# PDF
mmdc -i diagram.mmd -o diagram.pdf

# Dark theme
mmdc -i diagram.mmd -o diagram.svg -t dark

# Transparent background
mmdc -i diagram.mmd -o diagram.png -b transparent
```

## Tech Stack

- **SwiftUI** — UI framework
- **WebKit** (WKWebView) — Mermaid rendering engine
- **mermaid-cli** (`mmdc`) — export pipeline
- **xcodegen** — project generation

## License

MIT