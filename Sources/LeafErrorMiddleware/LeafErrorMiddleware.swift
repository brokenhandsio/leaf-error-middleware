import Vapor

/// Captures all errors and transforms them into an internal server error.
public final class LeafErrorMiddleware: Middleware, Service {
    /// The environment to respect when presenting errors.
    let environment: Environment

    /// Log destination
    let log: Logger

    /// Create a new ErrorMiddleware for the supplied environment.
    public init(environment: Environment, log: Logger) {
        self.environment = environment
        self.log = log
    }

    /// See `Middleware.respond`
    public func respond(to req: Request, chainingTo next: Responder) throws -> Future<Response> {
        // Must set the preferred renderer:
        // e.g. config.prefer(LeafRenderer.self, for: TemplateRenderer.self)
        let renderer = try req.make(TemplateRenderer.self)

        func handleError(with status: HTTPStatus) throws -> Future<Response> {
            if status == .notFound {
                do {
                    return try renderer
                        .render("404")
                        .encode(for: req)
                        .map(to: Response.self) { res in
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
            } catch {
                let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
                return try body.encode(for: req)
                    .map(to: Response.self) { res in
                        res.http.status = status
                        res.http.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
                        return res
                }
            }
        }

        do {
            return try next.respond(to: req)
                .flatMap(to: Response.self) { res in
                    if res.http.status.code >= HTTPResponseStatus.badRequest.code {
                        return try handleError(with: res.http.status)
                    } else {
                        return try res.encode(for: req)
                    }
            }
        } catch {
            return try handleError(with: HTTPStatus(error))
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
