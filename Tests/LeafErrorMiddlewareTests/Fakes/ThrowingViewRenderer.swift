import Vapor

class ThrowingViewRenderer: ViewRenderer {
    
    var shouldCache = false
    var shouldThrow = false
    
    private(set) var capturedContext: Node? = nil
    private(set) var leafPath: String? = nil
    func make(_ path: String, _ context: Node) throws -> View {
        if shouldThrow {
            throw TestError()
        }
        self.capturedContext = context
        self.leafPath = path
        return View(data: "Test".makeBytes())
    }
}
