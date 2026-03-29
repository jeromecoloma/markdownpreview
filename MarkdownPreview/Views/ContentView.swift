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
    @ObservedObject var previewSearchController: PreviewSearchController
    let openPanel: () -> Void
    let openDocument: (URL) -> Void

    @State private var fileDropState: FileDropState = .idle
    @State private var invalidDropFeedbackToken = UUID()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                recentFilesViewModel: recentFilesViewModel,
                currentFileURL: documentViewModel.currentFileURL,
                isLoading: documentViewModel.isLoading,
                openPanel: openPanel,
                openRecent: openRecentFile,
                removeRecent: removeRecentFile
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            Group {
                if documentViewModel.hasDocument {
                    ZStack {
                        MarkdownWebView(
                            html: documentViewModel.renderedHTML,
                            baseURL: documentViewModel.baseURL,
                            fileURL: documentViewModel.renderedFileURL,
                            requestID: documentViewModel.previewRequestID,
                            isSearchAvailable: documentViewModel.isTextSearchAvailable,
                            searchController: previewSearchController,
                            onFileDrop: openDroppedFile,
                            onDropStateChanged: updateDropTargetedState,
                            isFileSupported: DocumentViewModel.isSupportedMarkdownFile(_:),
                            onDiagnostics: { message in
                                documentViewModel.updatePreviewDiagnostics(message)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(documentViewModel.useNativeFallback ? 0.001 : 1)
                        .allowsHitTesting(!documentViewModel.useNativeFallback)
                        .accessibilityHidden(documentViewModel.useNativeFallback)

                        if documentViewModel.useNativeFallback {
                            NativeMarkdownPreview(markdown: documentViewModel.rawMarkdown)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: documentViewModel.useNativeFallback)
                    .overlay {
                        previewLoaderOverlay
                    }
                    .overlay(alignment: .topTrailing) {
                        if previewSearchController.isFindPresented,
                           documentViewModel.hasDocument,
                           !documentViewModel.useNativeFallback {
                            PreviewFindBar(searchController: previewSearchController)
                                .padding(.top, 18)
                                .padding(.trailing, 18)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                } else {
                    emptyState
                }
            }
            .background(backgroundGradient)
        }
        .navigationTitle(documentViewModel.navigationTitle)
        .onAppear {
            previewSearchController.setSearchAvailable(documentViewModel.isTextSearchAvailable)
        }
        .onChange(of: documentViewModel.isTextSearchAvailable) { isAvailable in
            previewSearchController.setSearchAvailable(isAvailable)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Open…", action: openPanel)

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

            Button("Choose .md File…", action: openPanel)
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
    private var previewLoaderOverlay: some View {
        if let message = documentViewModel.previewDiagnostics,
           documentViewModel.hasDocument,
           !documentViewModel.useNativeFallback {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 72, height: 72)

                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
                        .frame(width: 72, height: 72)

                    ProgressView()
                        .controlSize(.large)
                        .tint(.accentColor)
                }

                VStack(spacing: 6) {
                    Text(previewLoaderTitle)
                        .font(.headline.weight(.semibold))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 22, y: 10)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var previewLoaderTitle: String {
        guard let message = documentViewModel.previewDiagnostics?.lowercased() else {
            return "Preparing Preview"
        }

        if message.contains("rendering") {
            return "Rendering Preview"
        }

        return "Preparing Preview"
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

    private func openRecentFile(_ item: RecentFile) {
        guard let url = recentFilesViewModel.resolveURL(for: item) else {
            documentViewModel.presentedError = .init(message: "The bookmark for this file could not be restored.")
            return
        }

        openDocument(url)
    }

    private func removeRecentFile(_ item: RecentFile) {
        withAnimation(.easeInOut(duration: 0.18)) {
            recentFilesViewModel.remove(item)
        }
    }

    @MainActor
    private func openDroppedFile(_ url: URL) {
        fileDropState = .idle
        openDocument(url)
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

private struct PreviewFindBar: View {
    @ObservedObject var searchController: PreviewSearchController
    @FocusState private var isSearchFieldFocused: Bool

    private var canNavigateMatches: Bool {
        searchController.hasMatches
    }

    private var searchResultSummary: String? {
        guard searchController.totalMatches > 0 else {
            return nil
        }

        return "\(searchController.currentMatchIndex) of \(searchController.totalMatches)"
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchController.searchQuery },
            set: { searchController.updateSearchQuery($0) }
        )
    }

    private var hasSearchText: Bool {
        !searchController.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String? {
        if let summary = searchResultSummary {
            return summary
        }

        return searchController.searchStatusMessage
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find in document", text: searchBinding)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        searchController.findNext()
                    }

                Button {
                    searchController.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canNavigateMatches ? Color.accentColor : .secondary)
                .help("Find Previous")

                Button {
                    searchController.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canNavigateMatches ? Color.accentColor : .secondary)
                .help("Find Next")

                Divider()
                    .frame(height: 16)

                Button {
                    searchController.hideFindInterface()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close Find")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)

            if hasSearchText, let statusText {
                Text(statusText)
                    .font(searchResultSummary == nil ? .caption : .caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.10), radius: 12, y: 6)
            }
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: searchController.searchFieldFocusToken) { _ in
            isSearchFieldFocused = true
        }
        .onExitCommand {
            searchController.hideFindInterface()
        }
    }
}
