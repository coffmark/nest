import ArgumentParser
import Foundation
import NestCLI
import NestKit
import Logging

struct SwitchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switch",
        abstract: "Switch a version of an installed command."
    )

    @Argument(help: "A command name")
    var commandName: String

    @Argument
    var version: String?

    @Flag(name: .shortAndLong)
    var verbose: Bool = false

    mutating func run() async throws {
        let (nestDirectory, artifactBundleManager, logger) = setUp()

        guard let commands = artifactBundleManager.list()[commandName] else {
            logger.error("🪹 \(commandName) doesn't exist.", metadata: .color(.red))
            return
        }
        let candidates = commands.filter { $0.version == version || version == nil }

        do {
            if candidates.isEmpty,
               let version {
                logger.error("🪹 \(commandName) (\(version)) doesn't exist.", metadata: .color(.red))
            } else if candidates.count == 1 {
                try switchCommand(candidates[0], nestDirectory: nestDirectory, artifactBundleManager: artifactBundleManager, logger: logger)
            }
            else {
                let options = candidates.map { candidate in
                    let isLinked = artifactBundleManager.isLinked(name: commandName, commend: candidate)
                    return "\(candidate.version) (\(candidate.source)) \(isLinked ? "(Selected)".green : "")"}
                guard let selectedIndex = CLIUtil.getUserChoice(from: options) else {
                    logger.error("Unknown error")
                    return
                }
                let command = candidates[selectedIndex]
                try switchCommand(command, nestDirectory: nestDirectory, artifactBundleManager: artifactBundleManager, logger: logger)
            }
        } catch {
            logger.error(error)
            Foundation.exit(1)
        }
    }

    private func switchCommand(
        _ command: NestInfo.Command,
        nestDirectory: NestDirectory,
        artifactBundleManager: ArtifactBundleManager,
        logger: Logger
    ) throws {
        let binaryInfo = ExecutableBinary(
            commandName: commandName,
            binaryPath: nestDirectory.url(command.binaryPath),
            version: command.version,
            manufacturer: command.manufacturer
        )
        try artifactBundleManager.link(binaryInfo)
        logger.info("🪺 \(binaryInfo.commandName) (\(binaryInfo.version)) is installed.")
    }
}

extension SwitchCommand {
    private func setUp() -> (
        NestDirectory,
        ArtifactBundleManager,
        Logger
    ) {
        LoggingSystem.bootstrap()
        let configuration = Configuration.make(
            nestPath: ProcessInfo.processInfo.nestPath,
            logLevel: verbose ? .trace : .info
        )

        return (
            configuration.nestDirectory,
            configuration.artifactBundleManager,
            configuration.logger
        )
    }
}
