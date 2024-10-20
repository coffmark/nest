import AsyncOperations
import Foundation
import NestKit

public struct NestfileUpdater: Sendable {
    private let repositoryClientBuilder: GitRepositoryClientBuilder
    private let fileSystem: any FileSystem
    private let fileDownloader: any FileDownloader
    private let checksumCalculator: any ChecksumCalculator

    public init(
        repositoryClientBuilder: GitRepositoryClientBuilder,
        fileSystem: some FileSystem,
        fileDownloader: some FileDownloader,
        checksumCalculator: some ChecksumCalculator
    ) {
        self.repositoryClientBuilder = repositoryClientBuilder
        self.fileSystem = fileSystem
        self.fileDownloader = fileDownloader
        self.checksumCalculator = checksumCalculator
    }

    public func update(_ nestfile: Nestfile) async throws -> Nestfile {
        var nestfile = nestfile
        nestfile.targets = try await nestfile.targets.asyncMap(numberOfConcurrentTasks: .max) { target in
            try await updateTarget(target)
        }
        return nestfile
    }

    private func updateTarget(_ target: Nestfile.Target) async throws -> Nestfile.Target {
        switch target {
        case .repository(let repository):
            let newRepository = try await updateRepository(repository)
            return .repository(newRepository)
        case .zip(let zipURL):
            guard let url = URL(string: zipURL.zipURL) else { return target }
            let newZipURL = try await updateZip(url: url)
            return .zip(newZipURL)
        case .deprecatedZIP(let zipURL):
            guard let url = URL(string: zipURL.url) else {
                return .zip(Nestfile.ZIPURL(zipURL: zipURL.url, checksum: nil))
            }
            let newZipURL = try await updateZip(url: url)
            return .zip(newZipURL)
        }
    }

    private func updateRepository(_ repository: Nestfile.Repository) async throws -> Nestfile.Repository {
        guard let gitURL = GitURL.parse(string: repository.reference),
              case .url(let url) = gitURL
        else { return repository }

        let repositoryClient = repositoryClientBuilder.build(for: url)
        let assetInfo = try await repositoryClient.fetchAssets(repositoryURL: url, version: .latestRelease)
        let selector = ArtifactBundleAssetSelector()
        guard let selectedAsset = selector.selectArtifactBundle(from: assetInfo.assets, fileName: repository.assetName) else {
            return Nestfile.Repository(
                reference: repository.reference,
                version: assetInfo.tagName,
                assetName: nil,
                checksum: nil
            )
        }

        if !selectedAsset.url.needsUnzip {
            return Nestfile.Repository(
                reference: repository.reference,
                version: assetInfo.tagName,
                assetName: selectedAsset.fileName,
                checksum: nil
            )
        }

        let checksum = try await downloadZIP(url: selectedAsset.url)
        return Nestfile.Repository(
            reference: repository.reference,
            version: assetInfo.tagName,
            assetName: selectedAsset.fileName,
            checksum: checksum
        )
    }

    private func updateZip(url: URL) async throws -> Nestfile.ZIPURL {
        let checksum = try await downloadZIP(url: url)
        return Nestfile.ZIPURL(zipURL: url.absoluteString, checksum: checksum)
    }

    private func downloadZIP(url: URL) async throws -> String? {
        let downloadedFilePath = try await fileDownloader.download(url: url)
        let downloadedZipFilePath = fileSystem.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try fileSystem.removeItemIfExists(at: downloadedZipFilePath)
        try fileSystem.copyItem(at: downloadedFilePath, to: downloadedZipFilePath)

        let checksum = try await checksumCalculator.calculate(downloadedZipFilePath.path())
        return checksum
    }
}
