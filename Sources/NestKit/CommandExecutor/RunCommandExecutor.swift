import Logging

public struct RunExecutor {
    private let executor: any ProcessExecutor
    
    public init(executor: any ProcessExecutor) {
        self.executor = executor
    }
    
    public func run(binaryPath: String, arguments: [String]) async throws {
        _ = try await executor.execute(command: binaryPath, arguments)
    }
}
