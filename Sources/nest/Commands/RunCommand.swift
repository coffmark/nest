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
        
        let runCommandExecutor: RunCommandExecutor
        
        do {
            runCommandExecutor = try RunCommandExecutor(arguments: arguments, nestfile: nestfile)
        } catch let error as RunCommandExecutorError {
            switch error {
            case .notSpecifiedReference:
                logger.error("`owner/repository` is not specified.", metadata: .color(.red))
            case .invalidFormatReference:
                logger.error("Invalid format: \(arguments), expected owner/repository", metadata: .color(.red))
            case .notFoundExpectedVersion:
                logger.error("Failed to find expected version in nestfile", metadata: .color(.red))
            }
            return
        }
        
        guard let installTarget = InstallTarget(argument: runCommandExecutor.referenceName),
              case let .git(gitURL) = installTarget,
              let gitVersion = GitVersion(argument: runCommandExecutor.expectedVersion)
        else {
            return
        }

        guard let binaryRelativePath = try await runCommandExecutor.getBinaryRelativePath(
            hasFetchAndInstalled: false,
            gitURL: gitURL,
            gitVersion: gitVersion,
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
                command: "\(nestDirectory.rootDirectory.relativePath)\(binaryRelativePath)",
                runCommandExecutor.subcommands
            )
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
