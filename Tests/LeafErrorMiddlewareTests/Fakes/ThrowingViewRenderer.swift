import Vapor

class ThrowingViewRenderer {
    
    var shouldCache = false
    var shouldThrow = false
    
    private(set) var capturedContext: [String:String]? = nil
    private(set) var leafPath: String? = nil

    func make(_ path: String, _ context: [String:String]) throws -> View {
        if shouldThrow {
            throw TestError()
        }
        self.capturedContext = context
        self.leafPath = path
        return View(data: "Test".convertToData())
    }
}
