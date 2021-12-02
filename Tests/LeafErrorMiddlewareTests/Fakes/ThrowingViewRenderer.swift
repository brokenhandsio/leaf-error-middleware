import Vapor

class ThrowingViewRenderer: ViewRenderer {
    var shouldCache = false
    var eventLoop: EventLoop
    var shouldThrow = false

    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }

    private(set) var capturedContext: Encodable?
    private(set) var leafPath: String?
    func render<E>(_ name: String, _ context: E) -> EventLoopFuture<View> where E: Encodable {
        self.capturedContext = context
        self.leafPath = name
        if self.shouldThrow {
            return self.eventLoop.makeFailedFuture(TestError())
        }
        let response = "Test"
        var byteBuffer = ByteBufferAllocator().buffer(capacity: response.count)
        byteBuffer.writeString(response)
        return self.eventLoop.future(View(data: byteBuffer))
    }

    func `for`(_ request: Request) -> ViewRenderer {
        return self
    }
}
