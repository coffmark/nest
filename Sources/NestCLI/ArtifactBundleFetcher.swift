import Foundation
import Logging
import NestKit

public struct ArtifactBundleFetcher {
    private let workingDirectory: URL
    private let fileStorage: any FileStorage
    private let fileDownloader: any FileDownloader
    private let nestInfoController: NestInfoController
    private let repositoryClientBuilder: GitRepositoryClientBuilder
    private let logger: Logger

    public init(
        workingDirectory: URL,
        fileStorage: some FileStorage,
        fileDownloader: some FileDownloader,
        nestInfoController: NestInfoController,
        repositoryClientBuilder: GitRepositoryClientBuilder,
        logger: Logger
    ) {
        self.workingDirectory = workingDirectory
        self.fileStorage = fileStorage
        self.fileDownloader = fileDownloader
        self.nestInfoController = nestInfoController
        self.repositoryClientBuilder = repositoryClientBuilder
        self.logger = logger
    }
    
    /// Fetched an artifact bundle from the specified git repository.
    /// - Parameters:
    ///   - url: A url of a git repository
    ///   - version: A version which should be
    ///   - artifactBundleZipFileName: A name of artifact bundle ZIP file.
    ///   When it is `nil`, this function tries to resolve a file name by accessing Web API.
    public func fetchArtifactBundleFromGitRepository(
        for gitURL: URL,
        version: GitVersion,
        artifactBundleZipFileName: String?
    ) async throws -> [ExecutableBinary] {
        let resolvedAsset = try await resolveAsset(
            from: gitURL,
            version: version,
            artifactBundleZipFileName: artifactBundleZipFileName
        )
        let nestInfo = nestInfoController.getInfo()

        if ArtifactDuplicatedDetector.isAlreadyInstalled(zipURL: resolvedAsset.zipURL, in: nestInfo) {
            throw NestCLIError.alreadyInstalled
        }

        logger.info("📦 Found an artifact bundle, \(resolvedAsset.zipURL.lastPathComponent), for \(gitURL.lastPathComponent).")

        // Reset the existing directory.
        let repositoryDirectory = workingDirectory.appending(component: gitURL.fileNameWithoutPathExtension)
        try fileStorage.removeItemIfExists(at: repositoryDirectory)

        // Download the artifact bundle
        logger.info("🌐 Downloading the artifact bundle of \(gitURL.lastPathComponent)...")
        try await fileDownloader.download(url: resolvedAsset.zipURL, to: repositoryDirectory)
        logger.info("✅ Success to download the artifact bundle of \(gitURL.lastPathComponent).", metadata: .color(.green))

        // Get the current triple.
        let triple = try await TripleDetector(logger: logger).detect()
        logger.debug("The current triple is \(triple)")

        return try fileStorage.child(extension: "artifactbundle", at: repositoryDirectory)
            .map { artifactBundlePath in
                let repository = Repository(reference: .url(gitURL), version: resolvedAsset.tagName)
                let sourceInfo = ArtifactBundleSourceInfo(zipURL: resolvedAsset.zipURL, repository: repository)
                return try ArtifactBundle(at: artifactBundlePath, sourceInfo: sourceInfo)
            }
            .flatMap { bundle in try bundle.binaries(of: triple) }
    }

    public func downloadArtifactBundle(url: URL) async throws -> [ExecutableBinary] {
        let nestInfo = nestInfoController.getInfo()
        if ArtifactDuplicatedDetector.isAlreadyInstalled(zipURL: url, in: nestInfo) {
            throw NestCLIError.alreadyInstalled
        }

        let directory = workingDirectory.appending(component: url.fileNameWithoutPathExtension)
        try fileStorage.removeItemIfExists(at: directory)

        // Download the artifact bundle
        logger.info("🌐 Downloading the artifact bundle at \(url.absoluteString)...")
        try await fileDownloader.download(url: url, to: directory)
        logger.info("✅ Success to download the artifact bundle of \(url.lastPathComponent).", metadata: .color(.green))

        // Get the current triple.
        let triple = try await TripleDetector(logger: logger).detect()
        logger.debug("The current triple is \(triple)")

        return try fileStorage.child(extension: "artifactbundle", at: directory)
            .compactMap { artifactBundlePath in
                let sourceInfo = ArtifactBundleSourceInfo(zipURL: url, repository: nil)
                return try ArtifactBundle(at: artifactBundlePath, sourceInfo: sourceInfo)
            }
            .flatMap { bundle in try bundle.binaries(of: triple) }
    }

    private func resolveAsset(
        from url: URL,
        version: GitVersion,
        artifactBundleZipFileName fileName: String?
    ) async throws -> ResolvedAsset {
        if let fileName {
            guard case .tag(let version) = version else {
                logger.debug("\(fileName) is specified but the version is not a tag.", metadata: .color(.red))
                throw ArtifactBundleFetcherError.noTagSpecified
            }

            let artifactBundleZipURL = GitHubURLBuilder.assetDownloadURL(url, version: version, fileName: fileName)
            logger.debug("Resolved artifact bundle zip URL: \(artifactBundleZipURL.absoluteString).")
            let asset = ResolvedAsset( zipURL: artifactBundleZipURL, fileName: fileName, tagName: version)
            return asset
        }

        let repositoryClient = repositoryClientBuilder.build(for: url)
        let assetInfo = try await repositoryClient.fetchAssets(repositoryURL: url, version: version)
        // Choose an asset which may be an artifact bundle.
        guard let selectedAsset = ArtifactBundleAssetSelector().selectArtifactBundle(from: assetInfo.assets) else {
            throw ArtifactBundleFetcherError.noCandidates
        }
        return ResolvedAsset(
            zipURL: selectedAsset.url,
            fileName: selectedAsset.fileName,
            tagName: assetInfo.tagName
        )
    }
}

extension ArtifactBundle {
    func binaries(of triple: String) throws -> [ExecutableBinary] {
        try info.artifacts.flatMap { name, artifact in
            let binaries = artifact.variants
                .filter { variant in variant.supportedTriples.contains(triple) }
                .map { variant in variant.path }
                .map { variantPath in rootDirectory.appending(path: variantPath) }
                .map { binaryPath in
                    ExecutableBinary(
                        commandName: name,
                        binaryPath: binaryPath,
                        version: artifact.version,
                        manufacturer: .artifactBundle(sourceInfo: sourceInfo)
                    )
                }
            if binaries.isEmpty {
                throw ArtifactBundleFetcherError.unsupportedTriple
            }
            return binaries
        }
    }
}

public enum ArtifactBundleFetcherError: LocalizedError {
    case noCandidates
    case noTagSpecified
    case unsupportedTriple

    public var errorDescription: String? {
        switch self {
        case .noCandidates: "No candidates for artifact bundle in the repository, please specify the file name."
        case .noTagSpecified: "No tag specified, please specify the tag."
        case .unsupportedTriple: "No binaries corresponding to the current triple."
        }
    }
}

struct ResolvedAsset {
    public var zipURL: URL
    public var fileName: String
    public var tagName: String
}
