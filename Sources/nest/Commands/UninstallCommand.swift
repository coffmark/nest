import ArgumentParser
import Foundation
import NestCLI
import NestKit
import Logging

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall a repository"
    )

    @Argument(help: "A command name you want to uninstall.")
    var commandName: String

    @Argument(help: "A version you want to uninstall")
    var version: String?

    @Flag(name: .shortAndLong)
    var verbose: Bool = false

    mutating func run() async throws {
        let (artifactBundleManager, logger) = setUp()

        let info = artifactBundleManager.list()

        let targetCommand = info[commandName, default: []].filter { command in
            command.version == version || version == nil
        }

        guard !targetCommand.isEmpty else {
            let message: Logger.Message =
                if let version {
                    "🪹 \(commandName) (\(version)) doesn't exist."
                } else {
                    "🪹 \(commandName) doesn't exist."
                }
            logger.error(message, metadata: .color(.red))
            Foundation.exit(1)
        }

        for command in targetCommand {
            try artifactBundleManager.uninstall(command: commandName, version: command.version)
            logger.info("🗑️ \(commandName) \(command.version) is uninstalled.")
        }
    }
}

extension UninstallCommand {
    private func setUp() -> (
        ArtifactBundleManager,
        Logger
    ) {
        LoggingSystem.bootstrap()
        let configuration = Configuration.make(
            nestPath: ProcessInfo.processInfo.nestPath,
            serverTokenEnvironmentVariableNames: [:],
            logLevel: verbose ? .trace : .info
        )

        return (
            configuration.artifactBundleManager,
            configuration.logger
        )
    }
}
