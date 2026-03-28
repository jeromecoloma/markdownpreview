import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var documentViewModel: DocumentViewModel
    @ObservedObject var recentFilesViewModel: RecentFilesViewModel

    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                recentFilesViewModel: recentFilesViewModel,
                currentFileURL: documentViewModel.currentFileURL,
                openPanel: presentOpenPanel,
                openRecent: openRecentFile
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            Group {
                if documentViewModel.hasDocument {
                    if documentViewModel.useNativeFallback {
                        NativeMarkdownPreview(markdown: documentViewModel.rawMarkdown)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MarkdownWebView(
                            html: documentViewModel.renderedHTML,
                            baseURL: documentViewModel.baseURL,
                            fileURL: documentViewModel.renderedFileURL,
                            onDiagnostics: { message in
                                documentViewModel.updatePreviewDiagnostics(message)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    emptyState
                }
            }
            .background(backgroundGradient)
            .overlay(alignment: .bottomLeading) {
                previewDiagnosticsOverlay
            }
        }
        .navigationTitle(documentViewModel.navigationTitle)
        .toolbar {
            ToolbarItemGroup {
                Button("Open…", action: presentOpenPanel)

                if documentViewModel.hasDocument {
                    Button("Reload") {
                        Task {
                            await documentViewModel.reloadCurrentDocument()
                        }
                    }
                }
            }
        }
        .overlay(alignment: .center) {
            dropOverlay
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
        .alert(
            "Couldn’t Open File",
            isPresented: Binding(
                get: { documentViewModel.presentedError != nil },
                set: { newValue in
                    if !newValue {
                        documentViewModel.presentedError = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    documentViewModel.presentedError = nil
                }
            },
            message: {
                Text(documentViewModel.presentedError?.message ?? "Something went wrong.")
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Preview Markdown instantly")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))

                Text("Open or drop a Markdown file to render GitHub-flavored content, Mermaid diagrams, and highlighted code.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }

            Button("Choose Markdown File…", action: presentOpenPanel)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.08),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var previewDiagnosticsOverlay: some View {
        if let message = documentViewModel.previewDiagnostics, documentViewModel.hasDocument {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(16)
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 10]))
                .foregroundStyle(Color.accentColor)
                .padding(24)
                .overlay {
                    dropOverlayCard
                }
                .transition(.opacity.combined(with: .scale))
        }
    }

    private var dropOverlayCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 42))
            Text("Drop Markdown to Preview")
                .font(.title3.weight(.semibold))
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = markdownTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(url)
    }

    private func openRecentFile(_ item: RecentFile) {
        guard let url = recentFilesViewModel.resolveURL(for: item) else {
            documentViewModel.presentedError = .init(message: "The bookmark for this file could not be restored.")
            return
        }

        openFile(url)
    }

    private func openFile(_ url: URL) {
        Task {
            let opened = await documentViewModel.open(url: url)
            if opened {
                await MainActor.run {
                    recentFilesViewModel.add(url: url)
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard
                        let data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    else {
                        return
                    }

                    Task { @MainActor in
                        openFile(url)
                    }
                }
                return true
            }
        }

        return false
    }

    private var markdownTypes: [UTType] {
        var types: [UTType] = []

        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }

        if let markdownLong = UTType(filenameExtension: "markdown") {
            types.append(markdownLong)
        }

        types.append(.plainText)
        return types
    }
}
