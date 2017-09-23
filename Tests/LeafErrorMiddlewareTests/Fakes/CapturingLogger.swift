import Vapor

class CapturingLogger: LogProtocol {
    var enabled: [LogLevel] = []
    
    private(set) var message: String?
    private(set) var logLevel: LogLevel?
    func log(_ level: LogLevel, message: String, file: String, function: String, line: Int) {
        self.message = message
        self.logLevel = level
    }
}
