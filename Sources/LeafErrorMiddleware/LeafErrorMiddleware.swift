import Vapor

/// Captures all errors and transforms them into an internal server error.
public final class LeafErrorMiddleware<T: Encodable>: AsyncMiddleware {
    let contextGenerator: (HTTPStatus, Error, Request) async throws -> T

    public init(contextGenerator: @escaping ((HTTPStatus, Error, Request) async throws -> T)) {
        self.contextGenerator = contextGenerator
    }

    /// See `Middleware.respond`
    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            let res = try await next.respond(to: request)
            if res.status.code >= HTTPResponseStatus.badRequest.code {
                return try await handleError(for: request, status: res.status, error: Abort(res.status))
            } else {
                return try await res.encodeResponse(for: request)
            }
        } catch {
            request.logger.report(error: error)
            switch error {
                case let abort as AbortError:
                    guard
                        abort.status.representsError
                    else {
                        if let location = abort.headers[.location].first {
                            return request.redirect(to: location)
                        } else {
                            return try await handleError(for: request, status: abort.status, error: error)
                        }
                    }
                    return try await handleError(for: request, status: abort.status, error: error)
                default:
                    return try await handleError(for: request, status: .internalServerError, error: error)
            }
        }
    }

    private func handleError(for request: Request, status: HTTPStatus, error: Error) async throws -> Response {
        if status == .notFound {
            do {
                let context = try await contextGenerator(status, error, request)
                let res = try await request.view.render("404", context).encodeResponse(for: request).get()
                res.status = status
                return res
            } catch {
                return try await renderServerErrorPage(for: status, request: request, error: error)
            }
        }
        return try await renderServerErrorPage(for: status, request: request, error: error)
    }

    private func renderServerErrorPage(for status: HTTPStatus, request: Request, error: Error) async throws -> Response {
        do {
            let context = try await contextGenerator(status, error, request)
            request.logger.error("Internal server error. Status: \(status.code) - path: \(request.url)")
            let res = try await request.view.render("serverError", context).encodeResponse(for: request).get()
            res.status = status
            return res
        } catch {
            let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
            request.logger.error("Failed to render custom error page - \(error)")
            let res = try await body.encodeResponse(for: request)
            res.status = status
            res.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
            return res
        }
    }
}

private extension HTTPResponseStatus {
    var representsError: Bool {
        return (HTTPResponseStatus.badRequest.code ... HTTPResponseStatus.networkAuthenticationRequired.code) ~= code
    }
}
