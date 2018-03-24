import Vapor
import Leaf

import Async
import Debugging
//import HTTP
import Service
import Foundation

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
        let renderer = try req.make(LeafRenderer.self)
        let promise = req.eventLoop.newPromise(Response.self)

        func handleError(with status: HTTPStatus) {
            if status == .notFound {
                do {
                    try renderer
                        .render("404")
                        .encode(for: req)
                        .do { res in
                            res.http.status = status
                            promise.succeed(result: res)
                    }
                } catch { /* swallow so we return the default view */ }
            }

            do {
                let parameters: [String:String] = [
                    "status": status.code.description,
                    "statusMessage": status.reasonPhrase
                ]
                try renderer
                    .render("serverError", parameters)
                    .encode(for: req)
                    .do { res in
                        res.http.status = status
                        promise.succeed(result: res)
                }
            } catch {
                let body = "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>"
                try! body.encode(for: req).do { res in
                    res.http.status = status
                    res.http.headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
                    promise.succeed(result: res)
                }
            }
        }

        do {
            try next.respond(to: req).do { res in
                if res.http.status != .ok {
                    handleError(with: res.http.status)
                } else {
                    promise.succeed(result: res)
                }
            }.catch { error in
                handleError(with: HTTPStatus(error))
            }
        } catch {
            handleError(with: HTTPStatus(error))
        }

        return promise.futureResult
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
