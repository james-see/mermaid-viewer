# 🧜‍♀️ Mermaid Viewer

A native macOS app for opening, previewing, and exporting [Mermaid](https://mermaid.js.org/) diagrams (`.mmd` files).

![Mermaid Viewer](MermaidViewer/AppIcon.icns)

## Features

- **Native macOS app** — built with SwiftUI + WebKit, not Electron
- **Live preview** — renders Mermaid 11 diagrams in-app
- **Light & Dark themes** — toggle between Mermaid light and dark themes
- **Source editor** — split view to edit `.mmd` source alongside the rendered diagram
- **Zoom controls**
  - Toolbar zoom in/out buttons with percentage display
  - **⌘+scroll** — zoom from mouse cursor position
  - **Shift+scroll** — horizontal pan
  - **Scroll** — vertical pan
  - **Box zoom** — draw a rectangle to zoom into a specific area
  - **Auto-fit** — fit diagram to window
- **Export** — convert diagrams to **SVG**, **PNG**, or **PDF** via `mmdc` (mermaid-cli)
- **Default app** — registers as the system default handler for `.mmd` files
- **App icon** — AI-generated mermaid + flowchart design

## Screenshots

![Mermaid Viewer Screenshot](https://raw.githubusercontent.com/james-see/mermaid-viewer/main/docs/screenshot.png)

## Installation

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- [Xcode](https://developer.apple.com/xcode/) 15+ (for building from source)
- [Node.js](https://nodejs.org/) + npm (for export feature only)

### Build from source

```bash
git clone https://github.com/james-see/mermaid-viewer.git
cd mermaid-viewer
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MermaidViewer.xcodeproj \
  -scheme MermaidViewer \
  -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
cp -R ~/Library/Developer/Xcode/DerivedData/MermaidViewer-*/Build/Products/Release/MermaidViewer.app /Applications/
```

### Set as default for `.mmd` files

```bash
brew install duti
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/MermaidViewer.app
duti -s com.james-see.mermaidviewer .mmd all
```

### Enable export

The export feature uses `mmdc` (mermaid-cli):

```bash
npm install -g @mermaid-js/mermaid-cli
```

## Usage

### Open a file

Double-click any `.mmd` file — it opens in Mermaid Viewer automatically.

Or launch the app and use **File → Open**.

### Export a diagram

1. Select format: **SVG**, **PNG**, or **PDF**
2. Click the **Export** button
3. Choose where to save

### Zoom controls

| Action | Input |
|--------|-------|
| Zoom in | Toolbar **+** button or **⌘+scroll up** |
| Zoom out | Toolbar **−** button or **⌘+scroll down** |
| Auto-fit | Toolbar **fit** button |
| Pan vertically | Scroll |
| Pan horizontally | **Shift+scroll** |
| Box zoom | Toggle box-zoom mode, then click-drag a rectangle |

## CLI conversion

You can also convert `.mmd` files from the command line using `mmdc`:

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
- **WebKit** (WKWebView) — Mermaid 11 rendering engine
- **CSS Transforms** — zoom/pan (replaces broken WKWebView.magnification)
- **mermaid-cli** (`mmdc`) — export pipeline
- **xcodegen** — Xcode project generation
- **Draw Things** — AI-generated app icon

## Project Structure

```
mermaid-viewer/
├── MermaidViewer/
│   ├── ContentView.swift        # Main UI, zoom, export, box-zoom
│   ├── MermaidViewerApp.swift   # App entry point
│   ├── Info.plist               # UTType registration for .mmd
│   └── AppIcon.icns             # App icon (all sizes)
├── project.yml                  # xcodegen project spec
├── Package.swift                # SPM manifest (legacy)
└── README.md
```

## Building & Contributing

```bash
# Generate Xcode project (requires xcodegen)
xcodegen generate

# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MermaidViewer.xcodeproj \
  -scheme MermaidViewer \
  -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Open in Xcode
open MermaidViewer.xcodeproj
```

## Roadmap

- [ ] Working auto-fit (measure SVG bounding box accurately)
- [ ] Sign & notarize for distribution
- [ ] Homebrew cask formula
- [ ] Drag-and-drop file opening
- [ ] Recent files menu
- [ ] Multiple tabs / windows

## License

MIT © [James Campbell](https://github.com/james-see)