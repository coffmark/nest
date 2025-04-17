import Foundation
import UniformTypeIdentifiers

extension URL {
    // TODO: この辺りを見れば良さそう
    public var fileNameWithoutPathExtension: String {
        lastPathComponent.replacingOccurrences(of: ".\(pathExtension)", with: "")
    }

    public var needsUnzip: Bool {
        let utType = UTType(filenameExtension: pathExtension)
        return utType?.conforms(to: .zip) ?? false
    }
}
