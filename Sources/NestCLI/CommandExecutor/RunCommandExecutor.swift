import Logging
import NestKit

// TODO: ドキュメントコメント
public struct RunCommandExecutor {
    public let referenceName: String
    public let subcommands: [String]
    // TODO: 引数が重くなっているから見直す
    
    public init?(
        arguments: [String],
    ) {
        // validate reference name
        guard !arguments.isEmpty, arguments[0].contains("/") else { return nil }
        
        let referenceName = arguments[0]
        let subcommands: [String] = if arguments.count >= 2 {
            Array(arguments[1...])
        } else {
            []
        }
        
        self.referenceName = referenceName
        self.subcommands = subcommands
    }
    
    /// Get the version that matches the `owner/repo`
    public func getVersion(nestfile: Nestfile) -> String? {
        let version = nestfile.targets
            .compactMap { target -> String? in
                guard case let .repository(repository) = target,
                      repository.reference == referenceName || GitURL.parse(string: repository.reference)?.referenceName == referenceName
                else { return nil }
                return repository.version
            }
            .first

        guard let version else { return nil }
        return version
    }
    
    public func getBinarySymbolicPath(
        hasFetchAndInstalled: Bool,
        referenceName: String,
        gitURL: GitURL,
        gitVersion: GitVersion,
        expectedVersion: String,
        nestInfo: NestInfo,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger
    ) async throws -> String? {
        guard let binaryName = getBinaryName(from: referenceName, nestInfo: nestInfo),
              // TODO: symbolic pathからバイナリを見てもいいけど、NestInfoとかである実体のバイナリをそもそも取得できれば、不要そう
              // TODO: 明日ここから
              let symbolicPath = try? artifactBundleManager.linkedFilePath(commandName: binaryName),
              // TODO: expectedVersionがcontainsだけでいいのか？
              symbolicPath.contains(expectedVersion)
        else {
            // attempt installation only once
            guard !hasFetchAndInstalled else { return nil }
            
            try await fetchAndInstallExecutableBinary(
                gitURL: gitURL,
                gitVersion: gitVersion,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
            return try await getBinarySymbolicPath(
                hasFetchAndInstalled: true,
                referenceName: referenceName,
                gitURL: gitURL,
                gitVersion: gitVersion,
                expectedVersion: expectedVersion,
                nestInfo: nestInfo,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
        }
        
        return symbolicPath
    }
}

private extension RunCommandExecutor {
    /// Get binary name from `owner/repo`
    private func getBinaryName(from referenceName: String, nestInfo: NestInfo) -> String? {
        let repositoryName = referenceName.split(separator: "/").last?.lowercased() ?? ""

        // Since repository names typically match binary names, we search for an exact match with the key name.
        let commands = nestInfo.commands
            .first { $0.key == repositoryName }
        
        guard let binaryName = commands?.key else {
            return nestInfo.commands
                .first {
                    let command = $0.value.first {
                        switch $0.manufacturer {
                        case let .artifactBundle(sourceInfo):
                            return sourceInfo.zipURL.referenceName == referenceName
                        case let .localBuild(repository):
                            return repository.reference.referenceName == referenceName
                        }
                    }
                    return command != nil
                }?.key
        }
        return binaryName
    }
    
    
    private func fetchAndInstallExecutableBinary(
        gitURL: GitURL,
        gitVersion: GitVersion,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger
    ) async throws {
        let executableBinaries = try await executableBinaryPreparer.fetchOrBuildBinariesFromGitRepository(
            at: gitURL,
            version: gitVersion,
            artifactBundleZipFileName: nil,
            // TODO: checksumをskipしているからよくないかも
            checksum: .skip
        )

        for binary in executableBinaries {
            try artifactBundleManager.install(binary)
            logger.info("🪺 Success to install \(binary.commandName) version \(binary.version).")
        }
    }
}
