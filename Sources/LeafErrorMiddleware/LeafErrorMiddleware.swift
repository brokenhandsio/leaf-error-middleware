import Vapor
import HTTP

public final class LeafErrorMiddleware: Middleware {
    let log: LogProtocol
    let environment: Environment
    let viewRenderer: ViewRenderer
    public init(environment: Environment, log: LogProtocol, viewRenderer: ViewRenderer) {
        self.log = log
        self.environment = environment
        self.viewRenderer = viewRenderer
    }

    public func respond(to req: Request, chainingTo next: Responder) throws -> Response {
        do {
            return try next.respond(to: req)
        } catch {
            log.error(error)
            return make(with: req, for: error)
        }
    }

    public func make(with req: Request, for error: Error) -> Response {
        let status: Status = Status(error)
        if status == .notFound {
            do {
                let response = try viewRenderer.make("404", Node([:])).makeResponse()
                response.status = .notFound
                return response
            } catch { /* swallow so we return the default view */ }
        }
        
        do {
            let response = try viewRenderer.make("serverError").makeResponse()
            response.status = .internalServerError
            return response
        } catch {
            let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
            let response = Response(status: status, body: .data(body.makeBytes()))
            response.headers["Content-Type"] = "text/html; charset=utf-8"
            return response
        }
    }
}

extension LeafErrorMiddleware: ConfigInitializable {
    public convenience init(config: Config) throws {
        let log = try config.resolveLog()
        let viewRenderer = try config.resolveView()
        self.init(environment: config.environment, log: log, viewRenderer: viewRenderer)
    }
}

extension Status {
    internal init(_ error: Error) {
        if let abort = error as? AbortError {
            self = abort.status
        } else {
            self = .internalServerError
        }
    }
}
