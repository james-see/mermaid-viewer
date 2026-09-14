# Mermaid Viewer — Agent Guide

This file provides guidance for LLMs and human contributors working on the Mermaid Viewer repository.

## Project Overview

Mermaid Viewer is a native macOS app for opening, previewing, and exporting Mermaid diagrams (`.mmd` files). It renders Mermaid 11 diagrams via WebKit and exports to SVG/PNG/PDF via `mmdc` (mermaid-cli).

## Tech Stack

- **SwiftUI** — UI framework (macOS 14+)
- **WebKit** (WKWebView) — Mermaid 11 rendering engine (loaded from CDN)
- **CSS Transforms** — zoom/pan (WKWebView.magnification is broken; we use `transform: scale()` with `transform-origin: center center` instead)
- **mermaid-cli** (`mmdc`) — export pipeline (called via `npx`)
- **xcodegen** — Xcode project generation from `project.yml`
- **Draw Things** — AI-generated app icon

## Building

```bash
# Generate Xcode project (requires xcodegen: brew install xcodegen)
xcodegen generate

# Build from command line
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MermaidViewer.xcodeproj \
  -scheme MermaidViewer \
  -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Open in Xcode
open MermaidViewer.xcodeproj
```

## Key Architecture

### ContentView.swift (single-file app)

All code lives in `MermaidViewer/ContentView.swift`:

- **MermaidDocument** — FileDocument wrapper for `.mmd` files, registers UTType `com.mermaid.mmd`
- **MermaidContainerView** — NSView subclass that intercepts scroll events (Cmd+scroll zoom, Shift+scroll horizontal pan, default vertical scroll) and handles box-draw zoom mouse events
- **MermaidWebView** — NSViewRepresentable wrapping WKWebView. Loads HTML with Mermaid 11 from CDN. Zoom is applied via JavaScript CSS transforms, NOT WKWebView.magnification
- **Coordinator** — WKNavigationDelegate that polls for SVG render completion before applying auto-fit
- **ContentView** — SwiftUI main view with toolbar (theme toggle, source editor, zoom controls, box-zoom, export)

### Zoom System

**Do not use `WKWebView.setMagnification(_:centeredAt:)`** — it's broken and always zooms from content origin (top-left), ignoring the `centeredAt` point. All zoom is done via CSS:

```javascript
container.style.transform = 'translate(px, px) scale(N)';
container.style.transformOrigin = 'center center';
```

JS state tracks `window.__mermaidZoom`, `window.__mermaidPanX`, `window.__mermaidPanY`.

### Export

Export shells out to `npx -p @mermaid-js/mermaid-cli mmdc` with a temp `.mmd` file. Theme is passed via `-t dark` or `-t default`.

## Code Signing & Notarization

- **Certificate**: Developer ID Application: James Campbell (529AKJCKRC)
- **Apple ID**: jamesanthonycampbell@icloud.com
- **Team ID**: 529AKJCKRC
- **Entitlements**: `MermaidViewer/MermaidViewer.entitlements` (allow-jit, unsigned-executable-memory, disable-library-validation, network.client)
- **Manual signing**: `CODE_SIGN_STYLE: Manual` in project.yml (Automatic conflicts with Developer ID on CI)
- **Secure timestamp**: App is re-signed with `codesign --timestamp` after build (required for notarization)

## Releasing

Tag-triggered CI (`.github/workflows/release.yml`):

```bash
git tag v1.0.1
git push origin v1.0.1
```

Workflow: xcodegen generate → xcodebuild → re-sign with timestamp → notarytool submit+wait → stapler staple → create DMG → sign DMG → notarize DMG → staple DMG → GitHub release with DMG + SHA256.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `APPLE_DEVELOPER_ID_CERT` | Base64-encoded .p12 certificate |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | Password for the .p12 file |
| `APPLE_ID` | Apple ID email (jamesanthonycampbell@icloud.com) |
| `APPLE_ID_PASSWORD` | App-specific password (generate at appleid.apple.com) |
| `APPLE_TEAM_ID` | Developer team ID (529AKJCKRC) |
| `KEYCHAIN_PASSWORD` | Password for CI temporary keychain |

## GitHub Pages

Landing page at `docs/index.html`, deployed via `.github/workflows/deploy.yml` on push to main. Live at https://james-see.github.io/mermaid-viewer/

## Directory Structure

```
mermaid-viewer/
├── .github/workflows/
│   ├── deploy.yml              # GitHub Pages deploy
│   └── release.yml             # Tag-triggered signed release
├── docs/
│   └── index.html              # Landing page
├── MermaidViewer/
│   ├── ContentView.swift       # All app code
│   ├── MermaidViewerApp.swift   # App entry point
│   ├── Info.plist              # UTType registration for .mmd
│   ├── MermaidViewer.entitlements
│   └── AppIcon.icns            # App icon (all sizes)
├── project.yml                 # xcodegen project spec
├── Package.swift               # SPM manifest (legacy, not used for builds)
└── README.md
```

## Conventions

- **Single-file app**: All UI and logic in `ContentView.swift`. Don't split into multiple files unless it gets unwieldy.
- **No WKWebView.magnification**: Always use CSS transforms for zoom.
- **HTML is built in Swift**: The Mermaid HTML template is a string literal in `loadHTML()`. Escapes `&`, `<`, `>`.
- **Mermaid from CDN**: `https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js` — no bundled Mermaid.
- **xcodegen, not SPM**: The Xcode project is generated from `project.yml`. SPM `Package.swift` is legacy and doesn't build SwiftUI macros correctly with CommandLineTools.
- **.env is gitignored**: Contains Apple app-specific password. Never commit.

## Known Issues / Roadmap

- Auto-fit doesn't work reliably (SVG bounding box measurement is inconsistent)
- No drag-and-drop file opening
- No recent files menu
- No multiple tabs/windows
