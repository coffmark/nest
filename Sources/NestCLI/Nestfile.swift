import Foundation
import NestKit
import Yams

public struct Nestfile: Codable {
    public let nestPath: String?
    public let targets: [Target]

    public init(nestPath: String?, targets: [Target]) {
        self.nestPath = nestPath
        self.targets = targets
    }

    public enum Target: Codable, Equatable {
        case repository(Repository)
        case deprecatedZIP(DeprecatedZIPURL)
        case zip(ZIPURL)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let repository = try? container.decode(Repository.self) {
                self = .repository(repository)
            } else if let zipURL = try? container.decode(ZIPURL.self) {
                self = .zip(zipURL)
            } else if let zipURL = try? container.decode(DeprecatedZIPURL.self) {
                self = .deprecatedZIP(zipURL)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected repository or zip URL")
            }
        }

        public var isDeprecatedZIP: Bool {
            switch self {
            case .deprecatedZIP: return true
            default: return false
            }
        }
    }

    public struct Repository: Codable, Equatable {
        /// A reference to a repository.
        ///
        /// The acceptable formats are the followings
        /// - `{owner}/{name}`
        /// - HTTPS URL
        /// - SSH URL.
        public var reference: String
        public var version: String?

        /// Specify an asset file name of an artifact bundle.
        /// If the name is not specified, the tool fetch the name by GitHub API.
        public var assetName: String?
        public var checksum: String?

        public init(reference: String, version: String?, assetName: String?, checksum: String?) {
            self.reference = reference
            self.version = version
            self.assetName = assetName
            self.checksum = checksum
        }
    }

    public struct DeprecatedZIPURL: Codable, Equatable {
        public var url: String

        public init(url: String) {
            self.url = url
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.url = try container.decode(String.self)
        }
    }

    public struct ZIPURL: Codable, Equatable {
        public var zipURL: String
        public var checksum: String?

        public init(zipURL: String, checksum: String?) {
            self.zipURL = zipURL
            self.checksum = checksum
        }

        enum CodingKeys: String, CodingKey {
            case zipURL = "zipURL"
            case checksum
        }
    }
}

extension Nestfile {
    public static func load(from path: String, fileSystem: some FileSystem) throws -> Nestfile {
        let url = URL(fileURLWithPath: path)
        let data = try fileSystem.data(at: url)
        return try YAMLDecoder().decode(Nestfile.self, from: data)
    }
}
