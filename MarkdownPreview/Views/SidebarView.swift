import SwiftUI

struct SidebarView: View {
    @ObservedObject var recentFilesViewModel: RecentFilesViewModel
    let currentFileURL: URL?
    let isLoading: Bool
    let openPanel: () -> Void
    let openRecent: (RecentFile) -> Void
    let removeRecent: (RecentFile) -> Void

    @State private var hoveredItemID: String?
    @State private var openingItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Recent Files")
                    .font(.headline)
                Spacer()
                Button("Open…", action: openPanel)
                    .buttonStyle(.borderedProminent)
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
            } else {
                ScrollViewReader { proxy in
                    List(recentFilesViewModel.recentFiles) { item in
                        ZStack(alignment: .trailing) {
                            Button {
                                openingItemID = item.id
                                openRecent(item)
                            } label: {
                                rowLabel(for: item)
                            }
                            .buttonStyle(
                                SidebarRecentFileButtonStyle(
                                    isSelected: isSelected(item),
                                    isHovered: hoveredItemID == item.id,
                                    isOpening: openingItemID == item.id && isLoading
                                )
                            )
                            .contentShape(Rectangle())

                            removeButton(for: item)
                        }
                        .id(item.id)
                        .onHover { isHovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                hoveredItemID = isHovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                removeRecent(item)
                            } label: {
                                Label("Remove from Recent Files", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.sidebar)
                    .onAppear {
                        scrollSelectedRow(using: proxy)
                    }
                    .onChange(of: currentFileURL) { _ in
                        scrollSelectedRow(using: proxy)
                    }
                    .onChange(of: recentFilesViewModel.recentFiles) { _ in
                        scrollSelectedRow(using: proxy)
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Drop a `.md` file anywhere in the window", systemImage: "arrow.down.doc")
                Label("Mermaid and syntax highlighting render offline", systemImage: "bolt.horizontal.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(20)
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
        guard let selectedID = recentFilesViewModel.recentFiles.first(where: isSelected)?.id else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(selectedID, anchor: .top)
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
            } else if isSelected(item) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func removeButton(for item: RecentFile) -> some View {
        let isVisible = hoveredItemID == item.id && openingItemID != item.id

        Button {
            removeRecent(item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Remove from Recent Files")
        .padding(.trailing, 12)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }
}

private struct SidebarRecentFileButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    let isOpening: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: borderWidth(isPressed: configuration.isPressed))
            }
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .animation(.easeInOut(duration: 0.16), value: isSelected)
            .animation(.easeInOut(duration: 0.16), value: isOpening)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.22)
        }

        if isOpening {
            return Color.accentColor.opacity(0.18)
        }

        if isSelected {
            return Color.accentColor.opacity(0.14)
        }

        if isHovered {
            return Color.primary.opacity(0.07)
        }

        return .clear
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed || isOpening {
            return Color.accentColor.opacity(0.55)
        }

        if isSelected {
            return Color.accentColor.opacity(0.28)
        }

        return .clear
    }

    private func borderWidth(isPressed: Bool) -> CGFloat {
        (isPressed || isOpening || isSelected) ? 1 : 0
    }
}
