import Vapor

class CapturingLogger: Logger {

    var enabled: [LogLevel] = []
    
    private(set) var message: String?
    private(set) var logLevel: LogLevel?

    func log(_ string: String, at level: LogLevel, file: String, function: String, line: UInt, column: UInt) {
        self.message = string
        self.logLevel = level
    }
}
