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
    
    enum E: Error {
        case notSupported
        // 使っていないかも
        case notFound
        case notFoundExpectedVersion
        case notFoundInstalledVersion
        case notFoundBinaryName
        case notFoundReferenceName
        case notFoundAssetURL
        case notFoundVersionInNestfile
    }
    
    private func validateBinaryName(_ arguments: [String]) throws -> String {
        guard arguments.count >= 1 else { throw E.notFoundBinaryName }
        return arguments[0]
    }
    
    private func getReferenceNameFromAssetURL(url: URL) throws -> String {
        guard url.pathComponents.count >= 3 else { throw E.notFoundAssetURL }
        return "\(url.pathComponents[1])/\(url.pathComponents[2])"
    }
    
    private func getReferenceName(binaryName: String, nestInfo: NestInfoController) throws -> String {
        guard let commands = nestInfo.getInfo().commands.first (where: { $0.key == binaryName })?.value else {
            throw E.notFoundReferenceName
        }
        
        for command in commands {
            switch command.manufacturer {
            case let .artifactBundle(sourceInfo):
                // TODO: zipURLだけではなく、referenceを持っていることを確認したい
                return try getReferenceNameFromAssetURL(url: sourceInfo.zipURL)
            case let .localBuild(repository):
                // TODO: あとで
                throw E.notFoundReferenceName
//                return repository.reference
            }
        }
        
        throw E.notFoundReferenceName
    }
    
    private func getVersionsInNestInfo(binaryName: String, nestInfo: NestInfoController) throws -> [String] {
        guard let commands = nestInfo.getInfo().commands.first(where: { $0.key == binaryName })?.value else {
            throw E.notFoundInstalledVersion
        }
        return commands.map { $0.version }
    }
    
    private func getExpectedVersion(referenceName: String, nestfile: Nestfile) throws -> String {
        guard let target = nestfile.targets
            .first (where: {
                guard case let .repository(repository) = $0 else { return false }
                return repository.reference == referenceName
            }),
              case let .repository(repository) = target,
              let version = repository.version
        else { throw E.notFoundVersionInNestfile }
        return version
    }
    
    private func runExecutableBinary(binaryRelativePath: String, arguments: [String], logger: Logger) throws {
        try RunExecutor(executor: NestProcessExecutor(logger: logger))
            .run(binaryPath: binaryRelativePath, arguments: arguments)
    }
    
    
    mutating func run() async throws {
        print("arguments", arguments)
        print("debug: verbose", verbose)
        
        let binaryName = try validateBinaryName(arguments)
        print("debug: binaryName", binaryName)
        
        let subcommands = Array(arguments[1...])
        print("debug: subcommands", subcommands)
        
        // TODO: FileSystemのmock対応
        let nestfile = try Nestfile.load(from: nestfilePath, fileSystem: FileManager.default)
        // TODO: 必要な分だけsetUpを実行する
        let (executableBinaryPreparer, nestDirectory, artifactBundleManager, logger) = setUp(nestfile: nestfile)
        
        let nestInfo = NestInfoController(directory: nestDirectory, fileSystem: FileManager.default)
        
        let referenceName = try getReferenceName(binaryName: binaryName, nestInfo: nestInfo)
        print("debug: referenceName", referenceName)
        
        let installedVersions = try getVersionsInNestInfo(binaryName: binaryName, nestInfo: nestInfo)
        print("debug: installedVersions", installedVersions)
    
        let expectedVersion = try getExpectedVersion(referenceName: referenceName, nestfile: nestfile)
        print("debug: expectedVersion", expectedVersion)
        
        
        // 1. x binaryName, referenceNameを受け取る
        // 2. x referenceNameに一致するnestfileに記載のバージョンを取得する
        // 3. x binary のreadlinkを実行し、向き先を確認する
        // 4. binaryPathが一致するのをnestInfoから取得する
        // 5. そのnestInfoからバージョンを取得し、一致するかどうかを確認する
        
        // Get installed symbolic link path
        
        // TODO: ちゃんとやるなら、nestinfoに含まれているかどうかまで確認する必要がある
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
                arguments: arguments,
                logger: logger
            )
            return
        }
        
        print("debug: nestfile.nestPath", nestfile.nestPath)
        print("debug: nestDirectory", nestDirectory.rootDirectory.relativePath)
        print("debug: symbolicPath", symbolicPath)
        // TODO: もしかするとmock対応が必要
        print("debug: FileManager.default.currentDirectoryPath", FileManager.default.currentDirectoryPath)
        
        
        try runExecutableBinary(
            binaryRelativePath: "\(nestDirectory.rootDirectory.relativePath)\(symbolicPath)",
            arguments: arguments,
            logger: logger
        )
        
//
//        // Get version from .nest/info.json
//        let installedVersion = nestInfo.getInfo().commands
//            // TODO: この辺りをもっと綺麗に書きたい
//            .first { $0.key == binaryName }?.value
//            .first { $0.binaryPath == symbolicPath }
//            .map { $0.version }
//        
//        guard let installedVersion else { throw E.notFoundInstalledVersion }
//            
//        guard expectedVersionFromNestfile == installedVersion else {
//            try await fetchAndInstallExecutableBinary(
//                executableBinaryPreparer: executableBinaryPreparer,
//                artifactBundleManager: artifactBundleManager,
//                logger: logger,
//                expectedVersionFromNestfile: expectedVersionFromNestfile
//            )
//            return
//        }
//        logger.info("")
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
