import Vapor

@available(*, deprecated, renamed: "LeafErrorMiddlewareDefaultGenerator")
public enum LeafErorrMiddlewareDefaultGenerator {
    static func generate(_ status: HTTPStatus, _ error: Error, _ req: Request) -> EventLoopFuture<DefaultContext> {
        let reason: String?
        if let abortError = error as? AbortError {
            reason = abortError.reason
        } else {
            reason = nil
        }
        let context = DefaultContext(status: status.code.description, statusMessage: status.reasonPhrase, reason: reason)
        return req.eventLoop.future(context )
    }

    public static func build() -> LeafErrorMiddleware<DefaultContext> {
        LeafErrorMiddleware(contextGenerator: generate)
    }
}

public enum LeafErrorMiddlewareDefaultGenerator {
    static func generate(_ status: HTTPStatus, _ error: Error, _ req: Request) -> EventLoopFuture<DefaultContext> {
        let reason: String?
        if let abortError = error as? AbortError {
            reason = abortError.reason
        } else {
            reason = nil
        }
        let context = DefaultContext(status: status.code.description, statusMessage: status.reasonPhrase, reason: reason)
        return req.eventLoop.future(context )
    }

    public static func build() -> LeafErrorMiddleware<DefaultContext> {
        LeafErrorMiddleware(contextGenerator: generate)
    }
}
