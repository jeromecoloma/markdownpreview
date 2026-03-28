import Foundation

final class FileWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MarkdownPreview.FileWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@MainActor () -> Void)?

    func startWatching(url: URL, onChange: @escaping @MainActor () -> Void) throws {
        stop()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw CocoaError(.fileReadUnknown)
        }

        self.onChange = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedReload()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        onChange = nil
    }

    private func scheduleDebouncedReload() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let onChange = self.onChange else { return }
            Task { @MainActor in
                onChange()
            }
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: workItem)
    }

    deinit {
        stop()
    }
}
