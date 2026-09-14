import SwiftUI

@main
struct MermaidViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MermaidDocument()) { config in
            ContentView(document: config.$document)
                .frame(minWidth: 900, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Diagram") {
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}