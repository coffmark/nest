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
    
    @Argument(parsing: .captureForPassthrough)
    var arguments: [String]
    
    // TODO: デフォルトのコメント
    // TODO: なければhomeディレクトリ直下のnestfileを探す
    @Option(help: "A nestfile written in yaml. (Default: nestfile.yaml")
    var nestfilePath: String = "nestfile.yaml"
    
    enum RunCommandError: Error {
        case notFoundBinaryName
        case notFoundReferenceName
        case notFoundVersionInNestfile
    }
    
    // TODO: `nest run owner/repoで実行できるようにしておく
    
    private func getReference(binaryName: String, nestInfo: NestInfoController, logger: Logger) throws -> (referenceName: String, installedVersion: [String]) {
        guard let commands = nestInfo.getInfo().commands.first (where: { $0.key == binaryName })?.value else {
            throw RunCommandError.notFoundBinaryName
        }
        
        let referenceName = commands
            .compactMap { command in
                switch command.manufacturer {
                case let .artifactBundle(sourceInfo):
                    return sourceInfo.zipURL.referenceName ?? nil
                case let .localBuild(repository):
                    return repository.reference.referenceName ?? nil
                }
            }
            .first
        
        guard let referenceName else { throw RunCommandError.notFoundBinaryName }
        
        return (referenceName, commands.map { $0.version })
        
    }
    
    private func getExpectedVersion(referenceName: String, nestfile: Nestfile) throws -> String {
        let version = nestfile.targets
            .compactMap { target -> String? in
                guard case let .repository(repository) = target else { return nil }
                return repository.version
            }
            .first

        guard let version else {
            throw RunCommandError.notFoundVersionInNestfile
        }
        return version
    }
    
    private func runExecutableBinary(binaryRelativePath: String, subcommands: [String], logger: Logger) throws {
        try RunExecutor(executor: NestProcessExecutor(logger: logger))
            .run(binaryPath: binaryRelativePath, arguments: subcommands)
    }
    
    mutating func run() async throws {
        let nestfile = try Nestfile.load(from: nestfilePath, fileSystem: FileManager.default)
        let (executableBinaryPreparer, nestDirectory, artifactBundleManager, logger) = setUp(nestfile: nestfile)
        let nestInfo = NestInfoController(directory: nestDirectory, fileSystem: FileManager.default)
        
        guard !arguments.isEmpty else {
            logger.error("No binary name has been specified.", metadata: .color(.red))
            return
        }
        let binaryName = arguments[0]
        let subcommands = Array(arguments[1...])

        let (referenceName, _) = try getReference(binaryName: binaryName, nestInfo: nestInfo, logger: logger)
    
        let expectedVersion = try getExpectedVersion(referenceName: referenceName, nestfile: nestfile)
        print("debug: expectedVersion", expectedVersion)

        guard let symbolicPath = try? artifactBundleManager.linkedFilePath(commandName: binaryName),
              symbolicPath.contains(expectedVersion)
        else {
            try await fetchAndInstallExecutableBinary(
                binaryName: binaryName,
                referenceName: referenceName,
                executableBinaryPreparer: executableBinaryPreparer,
                artifactBundleManager: artifactBundleManager,
                logger: logger,
                expectedVersion: expectedVersion
            )
            let symbolicPath = try artifactBundleManager.linkedFilePath(commandName: binaryName)
            guard symbolicPath.contains(expectedVersion) else {
                return
            }
            try runExecutableBinary(
                binaryRelativePath: "\(nestDirectory.rootDirectory.relativePath)\(symbolicPath)",
                subcommands: subcommands,
                logger: logger
            )
            return
        }
        
        print("debug: nestfile.nestPath", nestfile.nestPath)
        print("debug: nestDirectory", nestDirectory.rootDirectory.relativePath)
        print("debug: symbolicPath", symbolicPath)
        // TODO: もしかするとmock対応が必要
        print("debug: FileManager.default.currentDirectoryPath", FileManager.default.currentDirectoryPath)
        
        // TODO: `$ ...` は出力されるようにしたい
        try runExecutableBinary(
            binaryRelativePath: "\(nestDirectory.rootDirectory.relativePath)\(symbolicPath)",
            subcommands: subcommands,
            logger: logger
        )
    }
    
    private func fetchAndInstallExecutableBinary(
        binaryName: String,
        referenceName: String,
        executableBinaryPreparer: ExecutableBinaryPreparer,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger,
        expectedVersion: String
    ) async throws {
        logger.info("🪺 Start installation of \(binaryName) version \(expectedVersion).", metadata: .color(.green))
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
