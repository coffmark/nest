import ArgumentParser
import Foundation
import NestKit
import NestCLI
import Logging

// TODO: テストを書きたい
// TODO: verbose有無, arguments有無
// TODO: nestfileが見つかる場合、ホームディレクトリ直下に見つかる場合


struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        // TODO: abstract
        abstract: "Run executable file on a given nestfile."
    )

    @Flag(help: "")
    var verbose: Bool = false
    
    @Option(help: "")
    var noInstall: Bool = false

    // TODO: デフォルトのコメント
    // TODO: なければhomeディレクトリ直下のnestfileを探す
    @Option(help: "A nestfile written in yaml. (Default: nestfile.yaml")
    var nestfilePath: String = "nestfile.yaml"
    
    @Argument(parsing: .captureForPassthrough)
    var arguments: [String]
    
    enum E: Error {
        case notFoundBinaryName
        case notFoundVersionInNestfile
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
    
    private func getExpectedVersion(referenceName: String, nestfile: Nestfile) throws -> String {
        let version = nestfile.targets
            .compactMap { target -> String? in
                guard case let .repository(repository) = target,
                      repository.reference == referenceName
                else { return nil }
                return repository.version
            }
            .first

        guard let version else {
            // TODO: nestfile.yamlに記載がなかった時の対応
            throw E.notFoundVersionInNestfile
        }
        return version
    }
    
    private func runExecutableBinary(binaryRelativePath: String, subcommands: [String], logger: Logger) throws {
        try RunExecutor(executor: NestProcessExecutor(logger: logger))
            .run(binaryPath: binaryRelativePath, arguments: subcommands)
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
            guard !hasFetchAndInstalled else { return nil }
            
            try await fetchAndInstallExecutableBinary(
                referenceName: referenceName,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger,
                expectedVersion: expectedVersion
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
    
    
    mutating func run() async throws {
        let nestfile = try Nestfile.load(from: nestfilePath, fileSystem: FileManager.default)
        let (executableBinaryPreparer, nestDirectory, artifactBundleManager, logger) = setUp(nestfile: nestfile)
        let nestInfo = NestInfoController(directory: nestDirectory, fileSystem: FileManager.default)
        
        // validate reference name
        guard !arguments.isEmpty else {
            logger.error("No owner/repository has been specified.", metadata: .color(.red))
            return
        }
        guard arguments[0].contains("/") else {
            logger.error("Invalid format: \(arguments[0]), expected owner/repository", metadata: .color(.red))
            return
        }
        
        let referenceName = arguments[0]
        let subcommands: [String] = if arguments.count >= 2 {
            Array(arguments[1...])
        } else {
            []
        }
        let expectedVersion = try getExpectedVersion(referenceName: referenceName, nestfile: nestfile)
        print("debug: expectedVersion", expectedVersion)
        print("debug: nestfile.nestPath", nestfile.nestPath)
        print("debug: nestDirectory", nestDirectory.rootDirectory.relativePath)
        print("debug: FileManager.default.currentDirectoryPath", FileManager.default.currentDirectoryPath)
        
        guard let binaryRelativePath = try await getBinaryRelativePath(
            hasFetchAndInstalled: false,
            referenceName: referenceName,
            nestInfo: nestInfo,
            nestDirectory: nestDirectory,
            executableBinaryPreparer: executableBinaryPreparer,
            artifactBundleManager: artifactBundleManager,
            logger: logger,
            expectedVersion: expectedVersion
        ) else {
            logger.error("Failed to find binary path", metadata: .color(.red))
            return
        }
        
        // TODO: `$ ...` は出力されるようにしたい
        try runExecutableBinary(
            binaryRelativePath: binaryRelativePath,
            subcommands: subcommands,
            logger: logger
        )
    }
    
    private func fetchAndInstallExecutableBinary(
        referenceName: String,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger,
        expectedVersion: String
    ) async throws {
        logger.info("🪺 Start installation of \(referenceName) version \(expectedVersion).", metadata: .color(.green))
        guard let installTarget = InstallTarget(argument: referenceName),
              let gitVersion = GitVersion(argument: expectedVersion) else {
            return
        }
        guard case let .git(gitURL) = installTarget else {
            logger.error("artifact bundleを指定するのは考慮外")
            return
        }
        
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
