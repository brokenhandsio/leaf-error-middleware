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
        // Must set the preferred renderer:
        // e.g. config.prefer(LeafRenderer.self, for: TemplateRenderer.self)
        let renderer = try req.make(ViewRenderer.self)

        if status == .notFound {
            do {
                return try renderer.render("404").encode(for: req).map(to: Response.self) { res in
                    res.http.status = status
                    return res
                }
            } catch { /* swallow so we return the default view */ }
        }

        do {
            let parameters: [String:String] = [
                "status": status.code.description,
                "statusMessage": status.reasonPhrase
            ]
            return try renderer
                .render("serverError", parameters)
                .encode(for: req)
                .map(to: Response.self) { res in
                    res.http.status = status
                    return res
            }
        } catch let error {
            let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
            let logger = try req.make(Logger.self)
            logger.error("Failed to render custom error page - \(error)")
            return try body.encode(for: req)
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
