import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var recentFilesViewModel: RecentFilesViewModel
    @ObservedObject var keyboardAccessibilityController: KeyboardAccessibilityController
    let currentFileURL: URL?
    let isLoading: Bool
    let openPanel: () -> Void
    let openRecent: (RecentFile) -> Void
    let removeRecent: (RecentFile) -> Void
    let focusedField: FocusState<KeyboardFocusTarget?>.Binding

    @State private var hoveredItemID: String?
    @State private var openingItemID: String?
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Recent Files")
                    .font(.headline)
                Spacer()
                Button("Open…", action: openPanel)
                    .buttonStyle(.borderedProminent)
                    .focused(focusedField, equals: .sidebarOpenButton)
                    .accessibilityHint("Open a Markdown file.")
            }

            if recentFilesViewModel.recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No recent files yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Open or drop a Markdown file to start building a short list here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $keyboardAccessibilityController.selectedRecentFileID) {
                        ForEach(recentFilesViewModel.recentFiles) { item in
                            recentFileRow(for: item)
                        }
                    }
                    .listStyle(.sidebar)
                    .focused(focusedField, equals: .recentFilesList)
                    .accessibilityLabel("Recent files")
                    .accessibilityHint("Use arrow keys to move through files. Press Return or Space to open the selected file.")
                    .onAppear {
                        scrollSelectedRow(using: proxy)
                    }
                    .onChange(of: currentFileURL) { _ in
                        scrollSelectedRow(using: proxy)
                    }
                    .onChange(of: keyboardAccessibilityController.selectedRecentFileID) { _ in
                        scrollSelectedRow(using: proxy)
                    }
                    .onDeleteCommand(perform: performRemoveSelectedRecentFile)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Drop a `.md` file anywhere in the window", systemImage: "arrow.down.doc")
                Label("Use the arrow keys in Recent Files, Return to open, and Delete to remove", systemImage: "keyboard")
                Label("Mermaid and syntax highlighting render offline", systemImage: "bolt.horizontal.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(20)
        .onAppear {
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: isLoading) { loading in
            if !loading {
                openingItemID = nil
            }
        }
    }

    private func isSelected(_ item: RecentFile) -> Bool {
        guard let currentFileURL else { return false }
        return currentFileURL.lastPathComponent == item.fileName &&
            currentFileURL.deletingLastPathComponent().path == item.parentDirectory
    }

    private func scrollSelectedRow(using proxy: ScrollViewProxy) {
        guard let selectedID = keyboardAccessibilityController.selectedRecentFileID else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(selectedID, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func rowLabel(for item: RecentFile) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.parentDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if openingItemID == item.id && isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.accentColor)
            } else if shouldShowRemoveButton(for: item) {
                removeButton(for: item)
            } else if isSelected(item) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func recentFileRow(for item: RecentFile) -> some View {
        rowLabel(for: item)
            .tag(Optional(item.id))
            .contentShape(Rectangle())
            .background(rowBackground(for: item), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(rowBorderColor(for: item), lineWidth: rowBorderWidth(for: item))
            }
            .padding(.vertical, 4)
            .contextMenu {
                contextMenu(for: item)
            }
            .onHover { isHovering in
                hoveredItemID = isHovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            }
            .onTapGesture {
                activate(item)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.fileName)
            .accessibilityValue(isSelected(item) ? "Current preview" : item.parentDirectory)
            .accessibilityHint("Press Return or Space to open. Press Delete to remove.")
            .id(item.id)
    }

    @ViewBuilder
    private func contextMenu(for item: RecentFile) -> some View {
        Button("Open") {
            activate(item)
        }

        Button(role: .destructive) {
            removeRecent(item)
        } label: {
            Label("Remove from Recent Files", systemImage: "trash")
        }
    }

    private func activate(_ item: RecentFile) {
        openingItemID = item.id
        keyboardAccessibilityController.selectedRecentFileID = item.id
        openRecent(item)
    }

    private func shouldShowRemoveButton(for item: RecentFile) -> Bool {
        hoveredItemID == item.id || keyboardAccessibilityController.selectedRecentFileID == item.id
    }

    private func removeButton(for item: RecentFile) -> some View {
        Button {
            removeRecent(item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove from Recent Files")
    }

    private func rowBackground(for item: RecentFile) -> Color {
        if openingItemID == item.id && isLoading {
            return Color.accentColor.opacity(0.18)
        }

        if keyboardAccessibilityController.selectedRecentFileID == item.id || isSelected(item) {
            return Color.accentColor.opacity(0.14)
        }

        if hoveredItemID == item.id {
            return Color.primary.opacity(0.07)
        }

        return .clear
    }

    private func rowBorderColor(for item: RecentFile) -> Color {
        if openingItemID == item.id && isLoading {
            return Color.accentColor.opacity(0.55)
        }

        if keyboardAccessibilityController.selectedRecentFileID == item.id || isSelected(item) {
            return Color.accentColor.opacity(0.28)
        }

        return .clear
    }

    private func rowBorderWidth(for item: RecentFile) -> CGFloat {
        let isActive = openingItemID == item.id && isLoading
        let isSelectedRow = keyboardAccessibilityController.selectedRecentFileID == item.id || isSelected(item)
        return (isActive || isSelectedRow) ? 1 : 0
    }

    private func performOpenSelectedRecentFile() {
        guard
            keyboardAccessibilityController.focusedTarget == .recentFilesList,
            let selectedID = keyboardAccessibilityController.selectedRecentFileID,
            let item = recentFilesViewModel.item(withID: selectedID)
        else {
            return
        }

        activate(item)
    }

    private func performRemoveSelectedRecentFile() {
        guard let selectedID = keyboardAccessibilityController.selectedRecentFileID,
              let item = recentFilesViewModel.item(withID: selectedID) else {
            return
        }

        removeRecent(item)
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }

        keyMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard keyboardAccessibilityController.focusedTarget == .recentFilesList else {
            return event
        }

        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            return event
        }

        switch event.keyCode {
        case 36, 76, 49:
            performOpenSelectedRecentFile()
            return nil
        case 51, 117:
            performRemoveSelectedRecentFile()
            return nil
        default:
            return event
        }
    }
}
