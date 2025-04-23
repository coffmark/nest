import Testing
import NestCLI

struct RunCommandExecutorTests {
    @Test(arguments: [
        (["owner/repo"], false),
        (["owner/repo subcommand --option"], false),
        ([], true),
        (["command"], true),
    ])
    func initialization(arguments: [String], isNil: Bool) {
        let executor = RunCommandExecutor(arguments: arguments)
        #expect((executor == nil) == isNil)
    }
    
    @Test(arguments: [
        (Self.nestfile, ["owner/repo1"], "0.0.1"),
        (Self.nestfile, ["owner/repo2"], nil),
        (Self.nestfile, ["owner/repo3"], "0.0.3"),
        (Self.nestfile, ["owner/repo4"], "0.0.4")
    ])
    func getVersionTests(nestfile: Nestfile, arguments: [String], expectedVersion: String?) {
        #expect(RunCommandExecutor(arguments: arguments)?.getVersion(nestfile: nestfile) == expectedVersion)
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
                )
            ]
        )
    }
}
