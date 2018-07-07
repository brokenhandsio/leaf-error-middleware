import Vapor

class ThrowingViewRenderer: ViewRenderer, Service {

    var shouldCache = false
    var worker: Worker
    var shouldThrow = false

    init(worker: Worker) {
        self.worker = worker
    }

    private(set) var capturedContext: Encodable? = nil
    private(set) var leafPath: String? = nil
    func render<E>(_ path: String, _ context: E) -> EventLoopFuture<View> where E : Encodable {
        self.capturedContext = context
        self.leafPath = path
        if shouldThrow {
            return Future.map(on: worker) { throw TestError() }
        }
        return Future.map(on: worker) { return View(data: "Test".convertToData()) }
    }
}
