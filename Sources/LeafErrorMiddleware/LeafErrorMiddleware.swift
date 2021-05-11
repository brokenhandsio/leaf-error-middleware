import Vapor

public struct DefaultContext: Encodable {
    public let status: String?
    public let statusMessage: String?
    public let reason: String?
}

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

/// Captures all errors and transforms them into an internal server error.
public final class LeafErrorMiddleware<T: Encodable>: Middleware {

    let contextGenerator: ((HTTPStatus, Error, Request) -> EventLoopFuture<T>)

    public init(contextGenerator: @escaping ((HTTPStatus, Error, Request) -> EventLoopFuture<T>)) {
        self.contextGenerator = contextGenerator
    }
    
    /// See `Middleware.respond`
    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        return next.respond(to: request).flatMap { res in
            if res.status.code >= HTTPResponseStatus.badRequest.code {
                return self.handleError(for: request, status: res.status, error: Abort(res.status))
            } else {
                return res.encodeResponse(for: request)
            }
        }.flatMapError { error in
            request.logger.report(error: error)
            switch (error) {
            case let abort as AbortError:
                guard
                    abort.status.representsError
                    else {
                        if let location = abort.headers[.location].first {
                            return request.eventLoop.future(request.redirect(to: location))
                        } else {
                            return self.handleError(for: request, status: abort.status, error: error)
                        }
                }
                return self.handleError(for: request, status: abort.status, error: error)
            default:
                return self.handleError(for: request, status: .internalServerError, error: error)
            }
        }
    }
    
    private func handleError(for req: Request, status: HTTPStatus, error: Error) -> EventLoopFuture<Response> {
        if status == .notFound {
            return contextGenerator(status, error, req).flatMap { context in
                return req.view.render("404", context).encodeResponse(for: req).map { res in
                    res.status = status
                    return res
                }
            }.flatMapError { newError in
                return self.renderServerErrorPage(for: status, request: req, error: newError)
            }
        }
        return renderServerErrorPage(for: status, request: req, error: error)
    }
    
    private func renderServerErrorPage(for status: HTTPStatus, request: Request, error: Error) -> EventLoopFuture<Response> {
        return contextGenerator(status, error, request).flatMap { context in
                request.logger.error("Internal server error. Status: \(status.code) - path: \(request.url)")
                return request.view.render("serverError", context).encodeResponse(for: request).map { res in
                    res.status = status
                    return res
                }
            }.flatMapError { error -> EventLoopFuture<Response> in
            let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
            request.logger.error("Failed to render custom error page - \(error)")
            return body.encodeResponse(for: request).map { res in
                res.status = status
                res.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
                return res
            }
        }
    }
}

private extension HTTPResponseStatus {
    var representsError: Bool {
        return (HTTPResponseStatus.badRequest.code ... HTTPResponseStatus.networkAuthenticationRequired.code) ~= code
    }
}
