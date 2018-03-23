import Vapor

public final class LeafErrorMiddleware: Middleware {
    let log: Logger
    let environment: Environment
    let renderer: TemplateRenderer

    public init(environment: Environment, log: Logger, renderer: TemplateRenderer) {
        self.log = log
        self.environment = environment
        self.renderer = renderer
    }

    public func respond(to request: Request, chainingTo next: Responder) throws -> EventLoopFuture<Response> {
        do {
            return try next.respond(to: request)
        } catch {
            log.reportError(error, as: "Error")
            return make(with: request, for: error)
        }
    }

    public func make(with req: Request, for error: Error) -> EventLoopFuture<Response> {
        let status: HTTPStatus = HTTPStatus(error)
        if status == .notFound {
            do {
                let response = try renderer.render("404").encode(for: req)
                return response.map { res -> Response in
                    res.http.status = .notFound
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
                .map { res -> Response in
                    res.http.status = status
                    return res
            }
        } catch {
            let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
            return try! body.encode(for: req).map { res -> Response in
                res.http.status = status
                res.http.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
                return res
            }
        }
    }
}

extension LeafErrorMiddleware: Service { }

extension HTTPStatus {
    internal init(_ error: Error) {
        if let abort = error as? AbortError {
            self = abort.status
        } else {
            self = .internalServerError
        }
    }
}
