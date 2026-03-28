import SwiftUI

struct SidebarView: View {
    @ObservedObject var recentFilesViewModel: RecentFilesViewModel
    let currentFileURL: URL?
    let openPanel: () -> Void
    let openRecent: (RecentFile) -> Void

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
                        Button {
                            openRecent(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.fileName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(isSelected(item) ? .primary : .primary)
                                Text(item.parentDirectory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected(item) ? Color.accentColor.opacity(0.14) : .clear)
                                .padding(.vertical, 2)
                        )
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
}
