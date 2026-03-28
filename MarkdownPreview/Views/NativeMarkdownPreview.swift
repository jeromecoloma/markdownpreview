import Foundation
import SwiftUI

struct NativeMarkdownPreview: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Group {
                if let attributed {
                    Text(attributed)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(markdown)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var attributed: AttributedString? {
        try? AttributedString(markdown: markdown)
    }
}
