import Logging

public struct RunExecutor {
    private let executor: any ProcessExecutor
    
    public init(executor: any ProcessExecutor) {
        self.executor = executor
    }
    
    public func run(binaryPath: String, arguments: [String]) throws {
        try executor.execute2(command: binaryPath, arguments)
    }
}
