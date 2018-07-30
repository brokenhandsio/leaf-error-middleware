import Vapor

/// Captures all errors and transforms them into an internal server error.
public final class LeafErrorMiddleware: Middleware, Service {
    /// The environment to respect when presenting errors.
    let environment: Environment

    /// Create a new ErrorMiddleware for the supplied environment.
    public init(environment: Environment) {
        self.environment = environment
    }

    /// See `Middleware.respond`
    public func respond(to req: Request, chainingTo next: Responder) throws -> Future<Response> {
        do {
            return try next.respond(to: req).flatMap(to: Response.self) { res in
                if res.http.status.code >= HTTPResponseStatus.badRequest.code {
                    return try self.handleError(for: req, status: res.http.status)
                } else {
                    return try res.encode(for: req)
                }
            }
        } catch {
            return try handleError(for: req, status: HTTPStatus(error))
        }
    }

    private func handleError(for req: Request, status: HTTPStatus) throws -> Future<Response> {
        let renderer = try req.make(ViewRenderer.self)

        if status == .notFound {
            return try renderer.render("404").encode(for: req).map(to: Response.self) { res in
                res.http.status = status
                return res
            }.catchFlatMap { _ in
                return try self.renderServerErrorPage(for: status, request: req, renderer: renderer)
            }
        }

        return try renderServerErrorPage(for: status, request: req, renderer: renderer)
    }

    private func renderServerErrorPage(for status: HTTPStatus, request: Request, renderer: ViewRenderer) throws -> Future<Response> {
        let parameters: [String:String] = [
            "status": status.code.description,
            "statusMessage": status.reasonPhrase
        ]

        let logger = try request.make(Logger.self)
        logger.error("Internal server error. Status: \(status.code) - path: \(request.http.url)")

        return try renderer.render("serverError", parameters).encode(for: request).map(to: Response.self) { res in
            res.http.status = status
            return res
            }.catchFlatMap { error -> Future<Response> in
                let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
                let logger = try request.make(Logger.self)
                logger.error("Failed to render custom error page - \(error)")
                return try body.encode(for: request)
                    .map(to: Response.self) { res in
                        res.http.status = status
                        res.http.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
                        return res
                }
        }
    }
}

extension HTTPStatus {
    internal init(_ error: Error) {
        if let abort = error as? AbortError {
            self = abort.status
        } else {
            self = .internalServerError
        }
    }
}
