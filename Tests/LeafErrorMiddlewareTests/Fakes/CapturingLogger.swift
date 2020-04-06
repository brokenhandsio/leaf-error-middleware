import Vapor

class CapturingLogger: LogHandler {
    
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { return self.metadata[key] }
        set { self.metadata[key] = newValue }
    }
    
    var metadata: Logger.Metadata = [:]
    
    var logLevel: Logger.Level = .trace
    
    var enabled: [Logger.Level] = []
    
    private(set) var message: String?
    private(set) var logLevelUsed: Logger.Level?
    
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        self.message = message.description
        self.logLevelUsed = level
    }
}
