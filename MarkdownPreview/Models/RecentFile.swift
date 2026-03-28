import Foundation

struct RecentFile: Codable, Identifiable, Hashable {
    let id: String
    let fileName: String
    let parentDirectory: String
    let bookmarkData: Data

    init(id: String = UUID().uuidString, fileName: String, parentDirectory: String, bookmarkData: Data) {
        self.id = id
        self.fileName = fileName
        self.parentDirectory = parentDirectory
        self.bookmarkData = bookmarkData
    }
}
