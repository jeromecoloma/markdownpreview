import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileDropState {
    case idle
    case valid
    case invalid

    var isVisible: Bool {
        self != .idle
    }
}

struct ContentView: View {
    @ObservedObject var documentViewModel: DocumentViewModel
    @ObservedObject var recentFilesViewModel: RecentFilesViewModel

    @State private var fileDropState: FileDropState = .idle
    @State private var invalidDropFeedbackToken = UUID()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                recentFilesViewModel: recentFilesViewModel,
                currentFileURL: documentViewModel.currentFileURL,
                openPanel: presentOpenPanel,
                openRecent: openRecentFile,
                removeRecent: removeRecentFile
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            Group {
                if documentViewModel.hasDocument {
                    if documentViewModel.useNativeFallback {
                        NativeMarkdownPreview(markdown: documentViewModel.rawMarkdown)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onDrop(
                                of: [UTType.fileURL.identifier],
                                isTargeted: dropTargetBinding,
                                perform: handleDrop(providers:)
                            )
                    } else {
                        MarkdownWebView(
                            html: documentViewModel.renderedHTML,
                            baseURL: documentViewModel.baseURL,
                            fileURL: documentViewModel.renderedFileURL,
                            requestID: documentViewModel.previewRequestID,
                            onFileDrop: openDroppedFile,
                            onDropStateChanged: updateDropTargetedState,
                            isFileSupported: DocumentViewModel.isSupportedMarkdownFile(_:),
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
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: dropTargetBinding, perform: handleDrop(providers:))
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

                Text("Open or drop a `.md` file to render GitHub-flavored content, Mermaid diagrams, and highlighted code.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }

            Button("Choose .md File…", action: presentOpenPanel)
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
        if fileDropState.isVisible {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 10]))
                .foregroundStyle(dropOverlayBorderColor)
                .padding(24)
                .overlay {
                    dropOverlayCard
                }
                .transition(.opacity.combined(with: .scale))
        }
    }

    private var dropOverlayCard: some View {
        VStack(spacing: 10) {
            Image(systemName: dropOverlayIconName)
                .font(.system(size: 42))
            Text(dropOverlayTitle)
                .font(.title3.weight(.semibold))
            Text(dropOverlayMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

    private func removeRecentFile(_ item: RecentFile) {
        withAnimation(.easeInOut(duration: 0.18)) {
            recentFilesViewModel.remove(item)
        }
    }

    private func openFile(_ url: URL) {
        guard DocumentViewModel.isSupportedMarkdownFile(url) else {
            rejectFile(url)
            return
        }

        Task {
            let opened = await documentViewModel.open(url: url)
            if opened {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        recentFilesViewModel.add(url: url)
                    }
                }
            }
        }
    }

    @MainActor
    private func openDroppedFile(_ url: URL) {
        fileDropState = .idle
        openFile(url)
    }

    @MainActor
    private func updateDropTargetedState(_ state: FileDropState) {
        fileDropState = state
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
                        if DocumentViewModel.isSupportedMarkdownFile(url) {
                            openDroppedFile(url)
                        } else {
                            rejectFile(url)
                        }
                    }
                }
                return true
            }
        }

        return false
    }

    private var markdownTypes: [UTType] {
        UTType(filenameExtension: DocumentViewModel.supportedFileExtension).map { [$0] } ?? []
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { fileDropState == .valid },
            set: { isTargeted in
                if isTargeted {
                    fileDropState = .valid
                } else if fileDropState == .valid {
                    fileDropState = .idle
                }
            }
        )
    }

    private var dropOverlayBorderColor: Color {
        switch fileDropState {
        case .valid:
            return Color.accentColor
        case .invalid:
            return Color.red
        case .idle:
            return .clear
        }
    }

    private var dropOverlayIconName: String {
        switch fileDropState {
        case .valid:
            return "doc.badge.plus"
        case .invalid:
            return "nosign"
        case .idle:
            return "doc"
        }
    }

    private var dropOverlayTitle: String {
        switch fileDropState {
        case .valid:
            return "Drop .md File to Preview"
        case .invalid:
            return "This File Isn’t Allowed"
        case .idle:
            return ""
        }
    }

    private var dropOverlayMessage: String {
        switch fileDropState {
        case .valid:
            return "MarkdownPreview only accepts Markdown files with the .md extension."
        case .invalid:
            return "Only .md files can be opened here."
        case .idle:
            return ""
        }
    }

    @MainActor
    private func rejectFile(_ url: URL) {
        invalidDropFeedbackToken = UUID()
        let token = invalidDropFeedbackToken
        fileDropState = .invalid
        documentViewModel.presentedError = .init(message: DocumentViewModel.unsupportedFileMessage(for: url))

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                guard invalidDropFeedbackToken == token, fileDropState == .invalid else { return }
                fileDropState = .idle
            }
        }
    }
}
