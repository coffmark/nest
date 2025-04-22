import Testing
import NestCLI

struct RunCommandExecutorTests {
    @Test(arguments: [
        (arguments: ["owner/repo"], isNil: false),
        (arguments: ["owner/repo subcommand --option"], isNil: false),
        (arguments: [], isNil: true),
        (arguments: ["command"], isNil: true),
    ])
    func initialization(arguments: [String], isNil: Bool) {
        let executor = RunCommandExecutor(arguments: arguments)
        #expect((executor == nil) == isNil)
    }
    
    @Test(arguments: [Self.nestfile])
    func getVersionTests(nestfile: Nestfile) {
        let executor = RunCommandExecutor(arguments: ["owner/repo1"])
        #expect(executor?.getVersion(nestfile: nestfile) == "0.0.1")
        
        let executor2 = RunCommandExecutor(arguments: ["owner/repo2"])
        #expect(executor2?.getVersion(nestfile: nestfile) == nil)
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
            ]
        )
    }
}
