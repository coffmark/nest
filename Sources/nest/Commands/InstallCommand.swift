import ArgumentParser
import Foundation
import NestCLI
import NestKit
import Logging

struct InstallCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a repository"
    )
    
    @Flag
    var verbose: Bool = false
    
    @Argument(parsing: .captureForPassthrough)
    var list: [String]

    mutating func run() async throws {
        print("debug: list", list)
        print("debug: verbose", verbose)
    }
}

extension InstallCommand {
}
