import XCTest
import LeafErrorMiddleware
import Vapor
@testable import Logging

class LeafErrorMiddlewareTests: XCTestCase {
        
    // MARK: - Properties
    var app: Application!
    var viewRenderer: ThrowingViewRenderer!
    var logger = CapturingLogger()
    var eventLoopGroup: EventLoopGroup!
    
    // MARK: - Overrides
    override func setUpWithError() throws {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        viewRenderer = ThrowingViewRenderer(eventLoop: eventLoopGroup.next())
        LoggingSystem.bootstrapInternal { _ in
            return self.logger
        }
        app = Application(.testing, .shared(eventLoopGroup))

        app.views.use { _ in
            return self.viewRenderer
        }

        func routes(_ router: RoutesBuilder) throws {

            router.get("ok") { req in
                return "ok"
            }
            
            router.get("404") { req -> HTTPStatus in
                return .notFound
            }

            router.get("serverError") { req -> EventLoopFuture<Response> in
                throw Abort(.internalServerError)
            }

            router.get("unknownError") { req -> EventLoopFuture<Response> in
                throw TestError()
            }

            router.get("unauthorized") { req -> EventLoopFuture<Response> in
                throw Abort(.unauthorized)
            }
            
            router.get("future404") { req -> EventLoopFuture<Response> in
                return req.eventLoop.future(error: Abort(.notFound))
            }
            
            router.get("future403") { req -> EventLoopFuture<Response> in
                return req.eventLoop.future(error: Abort(.forbidden))
            }

            router.get("future303") { req -> EventLoopFuture<Response> in
                return req.eventLoop.future(error: Abort.redirect(to: "ok"))
            }
            
            router.get("future404NoAbort") { req -> EventLoopFuture<HTTPStatus> in
                return req.eventLoop.future(.notFound)
            }
        }

        try routes(app)
        
        app.middleware.use(LeafErrorMiddleware(environment: app.environment))
    }
    
    override func tearDownWithError() throws {
        app.shutdown()
        try eventLoopGroup.syncShutdownGracefully()
    }
    
    // MARK: - Tests
    
    func testThatValidEndpointWorks() throws {
        let response = try app.getResponse(to: "/ok")
        XCTAssertEqual(response.status, .ok)
    }
    
    func testThatRequestingInvalidEndpointReturns404View() throws {
        let response = try app.getResponse(to: "/unknown")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView() throws {
        let response = try app.getResponse(to: "/serverError")
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    func testThatErrorGetsLogged() throws {
        _ = try app.getResponse(to: "/serverError")
        XCTAssertNotNil(logger.message)
        XCTAssertEqual(logger.logLevelUsed, .error)
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFails() throws {
        viewRenderer.shouldThrow = true
        let response = try app.getResponse(to: "/serverError")
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(response.body.string, "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFailsFor404() throws {
        viewRenderer.shouldThrow = true
        let response = try app.getResponse(to: "/unknown")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(response.body.string, "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
    }

    func testMessageLoggedIfRendererThrows() throws {
        viewRenderer.shouldThrow = true
        _ = try app.getResponse(to: "/serverError")
        XCTAssertTrue(logger.message?.starts(with: "Failed to render custom error page") ?? false)
    }
    
    func testThatRandomErrorGetsReturnedAsServerError() throws {
        let response = try app.getResponse(to: "/unknownError")
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    func testThatUnauthorisedIsPassedThroughToServerErrorPage() throws {
        let response = try app.getResponse(to: "/unauthorized")
        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
        guard let contextDictionary = viewRenderer.capturedContext as? [String: String] else {
            XCTFail()
            return
        }
        XCTAssertEqual(contextDictionary["status"], "401")
        XCTAssertEqual(contextDictionary["statusMessage"], "Unauthorized")
    }
    
    func testNonAbort404IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testThatFuture404IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/future404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testFutureNonAbort404IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/future404NoAbort")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testThatFuture403IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/future403")
        XCTAssertEqual(response.status, .forbidden)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }

    func testThatRedirectIsNotCaught() throws {
        let response = try app.getResponse(to: "/future303")
        XCTAssertEqual(response.status, .seeOther)
        XCTAssertEqual(response.headers[.location].first, "ok")
    }
    
    func testAddingMiddlewareToRouteGroup() throws {
        app.shutdown()
        app = Application(.testing, .shared(eventLoopGroup))
        app.views.use { _ in
            return self.viewRenderer
        }
        let middlewareGroup = app.grouped(LeafErrorMiddleware(environment: app.environment))
        middlewareGroup.get("404") { req -> EventLoopFuture<Response> in
            req.eventLoop.makeFailedFuture(Abort(.notFound))
        }
        middlewareGroup.get("ok") { req in
            return "OK"
        }
        let validResponse = try app.getResponse(to: "ok")
        XCTAssertEqual(validResponse.status, .ok)
        let response = try app.getResponse(to: "404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
}

extension Application {
    func getResponse(to path: String) throws -> Response {
        let request = Request(application: self, method: .GET, url: URI(path: path), on: self.eventLoopGroup.next())
        return try self.responder.respond(to: request).wait()
    }
}
