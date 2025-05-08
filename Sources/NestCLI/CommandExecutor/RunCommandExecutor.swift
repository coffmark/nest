import Logging
import NestKit

// TODO: ドキュメントコメント
public struct RunCommandExecutor {
    /// `owner/repo` format
    public let referenceName: String
    public let subcommands: [String]
    public let expectedVersion: String
    // TODO: 引数が重くなっているから見直す
    
    public init(arguments: [String], nestfile: Nestfile) throws {
        // validate reference name
        guard !arguments.isEmpty else { throw RunCommandExecutorError.notSpecifiedReference }
        guard arguments[0].contains("/") else { throw RunCommandExecutorError.invalidFormatReference }
        
        let referenceName = arguments[0]
        let subcommands: [String] = if arguments.count >= 2 {
            Array(arguments[1...])
        } else {
            []
        }
        
        guard let expectedVersion = Self.getExpectedVersion(referenceName: referenceName, nestfile: nestfile) else {
            // While we could execute with the latest version, the bootstrap subcommand serves that purpose.
            // Therefore, we return an error when no version is specified.
            throw RunCommandExecutorError.notFoundExpectedVersion
        }
        
        self.referenceName = referenceName
        self.subcommands = subcommands
        self.expectedVersion = expectedVersion
    }

    // TODO: メソッド名を見直す
    public func getBinaryRelativePath(
        didAttemptInstallation: Bool,
        gitURL: GitURL,
        gitVersion: GitVersion,
        nestInfo: NestInfo,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger
    ) async throws -> String? {
        guard let binaryRelativePath = getBinaryRelativePathFromNestInfo(nestInfo: nestInfo) else {
            // attempt installation only once
            guard !didAttemptInstallation else { return nil }
            
            try await fetchAndInstallExecutableBinary(
                gitURL: gitURL,
                gitVersion: gitVersion,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
            return try await getBinaryRelativePath(
                didAttemptInstallation: true,
                gitURL: gitURL,
                gitVersion: gitVersion,
                nestInfo: nestInfo,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
        }
        return binaryRelativePath
    }
}

private extension RunCommandExecutor {
    /// Get the version that matches the `owner/repo`
    private static func getExpectedVersion(referenceName: String, nestfile: Nestfile) -> String? {
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
    
    /// Get binary relative path from `owner/repo`
    private func getBinaryRelativePathFromNestInfo(nestInfo: NestInfo) -> String? {
        let repositoryName = referenceName.split(separator: "/").last?.lowercased() ?? ""

        // Since repository names typically match binary names, we search for an exact match with the key name.
        let binaryRelativePath = nestInfo.commands
            .first { $0.key == repositoryName }?.value
            .first { $0.version == expectedVersion }?.binaryPath
        
        guard let binaryRelativePath else {
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
                }?.value
                .first { $0.version == expectedVersion }?.binaryPath
        }
        return binaryRelativePath
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
            // TODO: zipfilenameもnilにしているのでよくない
            artifactBundleZipFileName: nil,
            // TODO: checksumをskipしているからよくない
            checksum: .skip
        )

        for binary in executableBinaries {
            try artifactBundleManager.install(binary)
            logger.info("🪺 Success to install \(binary.commandName) version \(binary.version).")
        }
    }
}

// TODO: ドキュメントコメント
public enum RunCommandExecutorError: Error {
    case notSpecifiedReference
    case invalidFormatReference
    case notFoundExpectedVersion
}
