import Testing
@testable import NestCLI

struct RunCommandExecutorTests {
    @Test(arguments: [
        (["owner/repo1"], "owner/repo1", [], "0.0.1"),
        (["owner/repo1", "subcommand", "--option"], "owner/repo1", ["subcommand", "--option"], "0.0.1"),
        (["owner/repo3"], "owner/repo3", [], "0.0.3"),
        (["owner/repo4"], "owner/repo4", [], "0.0.4")
    ])
    func initialization(arguments: [String], referenceName: String, subcommands: [String], expectedVersion: String) throws {
        let executor = try RunCommandExecutor(arguments: arguments, nestfile: Self.nestfile)
        #expect(executor.referenceName == referenceName)
        #expect(executor.subcommands == subcommands)
        #expect(executor.expectedVersion == expectedVersion)
    }
    
    @Test(arguments: [
        ([], RunCommandExecutorError.notSpecifiedReference),
        (["command"], RunCommandExecutorError.invalidFormatReference),
        (["owner/repo2"], RunCommandExecutorError.notFoundExpectedVersion),
        (["owner/repo5"], RunCommandExecutorError.notFoundExpectedVersion)
    ])
    func initializationError(arguments: [String], error: RunCommandExecutorError) {
        #expect(throws: error, performing: {
            try RunCommandExecutor(arguments: arguments, nestfile: Self.nestfile)
        })
    }
}

extension RunCommandExecutorTests {
    static var nestfile: Nestfile {
        Nestfile(
            nestPath: "./.nest",
            targets: [
                .repository(
                    Nestfile.Repository(
                        reference: "owner/repo1",
                        version: "0.0.1",
                        assetName: nil,
                        checksum: nil
                    )
                ),
                .repository(
                    Nestfile.Repository(
                        reference: "owner/repo2",
                        version: nil,
                        assetName: nil,
                        checksum: nil
                    )
                ),
                .repository(
                    Nestfile.Repository(
                        reference: "https://github.com/owner/repo3",
                        version: "0.0.3",
                        assetName: nil,
                        checksum: nil
                    )
                ),
                .repository(
                    Nestfile.Repository(
                        reference: "git@github.com:owner/repo4.git",
                        version: "0.0.4",
                        assetName: nil,
                        checksum: nil
                    )
                ),
                .zip(
                    .init(
                        zipURL: "https://github.com/owner/repo5/releases/download/0.0.5/foo.artifactbundle.zip",
                        checksum: nil
                    )
                )
            ]
        )
    }
}
