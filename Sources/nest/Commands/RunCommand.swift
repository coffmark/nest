import ArgumentParser
import Foundation
import NestKit
import NestCLI
import Logging

// TODO: テストを書きたい
// TODO: nestfileが見つかる場合、ホームディレクトリ直下に見つかる場合

// TODO: ホームディレクトリ直下にある場合


struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        // TODO: abstract
        abstract: "Run executable file on a given nestfile."
    )

    @Flag(help: "")
    var verbose: Bool = false
    
    // TODO: noInstall対応
    @Option(help: "")
    var noInstall: Bool = false

    // TODO: デフォルトのコメント
    // TODO: なければhomeディレクトリ直下のnestfileを探す
    @Option(help: "A nestfile written in yaml. (Default: nestfile.yaml")
    var nestfilePath: String = "nestfile.yaml"
    
    @Argument(parsing: .captureForPassthrough)
    var arguments: [String]
    
    mutating func run() async throws {
        let nestfile = try Nestfile.load(from: nestfilePath, fileSystem: FileManager.default)
        let (executableBinaryPreparer, nestDirectory, artifactBundleManager, logger) = setUp(nestfile: nestfile)
        let nestInfoController = NestInfoController(directory: nestDirectory, fileSystem: FileManager.default)
        
        guard let runCommandExecutor = RunCommandExecutor(arguments: arguments),
              let installTarget = InstallTarget(argument: runCommandExecutor.referenceName),
              case let .git(gitURL) = installTarget
        else {
            logger.error("Invalid format: \(arguments), expected owner/repository", metadata: .color(.red))
            return
        }
        
        guard let expectedVersion = runCommandExecutor.getVersion(nestfile: nestfile),
              let gitVersion = GitVersion(argument: expectedVersion)
        else {
            logger.error("Failed to find expected version in \(nestfilePath)", metadata: .color(.red))
            return
        }

        guard let symbolicPath = try await runCommandExecutor.getBinarySymbolicPath(
            hasFetchAndInstalled: false,
            referenceName: runCommandExecutor.referenceName,
            gitURL: gitURL,
            gitVersion: gitVersion,
            expectedVersion: expectedVersion,
            nestInfo: nestInfoController.getInfo(),
            executableBinaryPreparer: executableBinaryPreparer,
            artifactBundleManager: artifactBundleManager,
            logger: logger
        ) else {
            logger.error("Failed to find binary path", metadata: .color(.red))
            return
        }

        _ = try await NestProcessExecutor(logger: logger)
            .execute(
                command: "\(nestDirectory.rootDirectory.relativePath)\(symbolicPath)",
                runCommandExecutor.subcommands
            )
    }
    
    
    private func getBinaryName(referenceName: String, nestInfo: NestInfoController) -> String? {
        let repositoryName = referenceName.split(separator: "/").last?.lowercased() ?? ""
        // Since repository names typically match binary names, we search for an exact match with the key name.
        let commands = nestInfo.getInfo().commands
            .first { $0.key == repositoryName }
        
        guard let binaryName = commands?.key else {
            return nestInfo.getInfo().commands
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
    
    private func getBinaryRelativePath(
        hasFetchAndInstalled: Bool,
        referenceName: String,
        nestInfo: NestInfoController,
        nestDirectory: NestDirectory,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger,
        expectedVersion: String
    ) async throws -> String? {
        guard let binaryName = getBinaryName(referenceName: referenceName, nestInfo: nestInfo),
              let symbolicPath = try? artifactBundleManager.linkedFilePath(commandName: binaryName),
              symbolicPath.contains(expectedVersion)
        else {
            // attempt installation only once
            guard !hasFetchAndInstalled else { return nil }
            
            try await fetchAndInstallExecutableBinary(
                referenceName: referenceName,
                expectedVersion: expectedVersion,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger
            )
            return try await getBinaryRelativePath(
                hasFetchAndInstalled: true,
                referenceName: referenceName,
                nestInfo: nestInfo,
                nestDirectory: nestDirectory,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger,
                expectedVersion: expectedVersion
            )
        }
        
        return "\(nestDirectory.rootDirectory.relativePath)\(symbolicPath)"
    }
    
    private func fetchAndInstallExecutableBinary(
        referenceName: String,
        expectedVersion: String,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger
    ) async throws {
        logger.info("🪺 Start installation of \(referenceName) version \(expectedVersion).", metadata: .color(.green))
        guard let installTarget = InstallTarget(argument: referenceName),
              let gitVersion = GitVersion(argument: expectedVersion) else {
            return
        }
        guard case let .git(gitURL) = installTarget else { return }
        
        let executableBinaries = try await executableBinaryPreparer.fetchOrBuildBinariesFromGitRepository(
            at: gitURL,
            version: gitVersion,
            artifactBundleZipFileName: nil,
            checksum: .skip
        )

        for binary in executableBinaries {
            try artifactBundleManager.install(binary)
            logger.info("🪺 Success to install \(binary.commandName) version \(binary.version).")
        }
    }
}

extension RunCommand {
    // TODO: 違い Bootstrap Commandとの
    private func setUp(nestfile: Nestfile) -> (
        ExecutableBinaryPreparer,
        NestDirectory,
        ArtifactBundleManager,
        Logger
    ) {
        LoggingSystem.bootstrap()
        let configuration = Configuration.make(
            // TODO: プロジェクトディレクトリでのnestPathとグローバルのnestPathが違っているのでテストするか実装を確認する
            nestPath: nestfile.nestPath ?? ProcessInfo.processInfo.nestPath,
            registryTokenEnvironmentVariableNames: nestfile.registries?.githubServerTokenEnvironmentVariableNames ?? [:],
            logLevel: .debug
        )

        return (
            configuration.executableBinaryPreparer,
            configuration.nestDirectory,
            configuration.artifactBundleManager,
            configuration.logger
        )
    }
}
