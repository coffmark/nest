import Logging
import NestKit

// TODO: ドキュメントコメント
public struct RunCommandExecutor {
    /// `owner/repo` format
    public let referenceName: String
    public let subcommands: [String]
    public let expectedVersion: String
    // TODO: 引数が重くなっているから見直す
    
    public init(arguments: [String], nestfile: Nestfile, nestfileController: NestfileController) throws {
        // validate reference name
        guard !arguments.isEmpty else { throw RunCommandExecutorError.notSpecifiedReference }
        guard arguments[0].contains("/") else { throw RunCommandExecutorError.invalidFormatReference }
        
        let referenceName = arguments[0]
        let subcommands: [String] = if arguments.count >= 2 {
            Array(arguments[1...])
        } else {
            []
        }
        
        guard let expectedVersion = nestfileController.fetchTarget(referenceName: referenceName, nestfile: nestfile)?.version else {
            // While we could execute with the latest version, the bootstrap subcommand serves that purpose.
            // Therefore, we return an error when no version is specified.
            throw RunCommandExecutorError.notFoundExpectedVersion
        }
        
        self.referenceName = referenceName
        self.subcommands = subcommands
        self.expectedVersion = expectedVersion
    }

    // TODO: メソッド名を見直す
    public func doSomething(
        didAttemptInstallation: Bool,
        gitURL: GitURL,
        gitVersion: GitVersion,
        nestInfo: NestInfo,
        nestInfoController: NestInfoController,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger
    ) async throws -> String? {
        guard let binaryRelativePath = nestInfoController.fetchCommand(referenceName: referenceName, version: expectedVersion)?.binaryPath
        else {
            // attempt installation only once
            guard !didAttemptInstallation else { return nil }
            
            try await fetchAndInstallExecutableBinary(
                gitURL: gitURL,
                gitVersion: gitVersion,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
            return try await doSomething(
                didAttemptInstallation: true,
                gitURL: gitURL,
                gitVersion: gitVersion,
                nestInfo: nestInfo,
                nestInfoController: nestInfoController,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
        }
        return binaryRelativePath
    }
}

private extension RunCommandExecutor {
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
