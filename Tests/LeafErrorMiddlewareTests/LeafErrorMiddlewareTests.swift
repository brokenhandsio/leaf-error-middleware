import XCTest
import LeafErrorMiddleware
@testable import Vapor

class LeafErrorMiddlewareTests: XCTestCase {
        
    // MARK: - Properties
    var app: Application!
    var viewRenderer: ThrowingViewRenderer!
    var logger: CapturingLogger!
    var eventLoopGroup: EventLoopGroup!
    
    // MARK: - Overrides
    override func setUpWithError() throws {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        viewRenderer = ThrowingViewRenderer(eventLoop: eventLoopGroup.next())
        logger = CapturingLogger()
        app = Application(.testing, .shared(eventLoopGroup))

//        services.register(ViewRenderer.self) { container -> ThrowingViewRenderer in
//            return self.viewRenderer
//        }
//        services.register(Logger.self) { container -> CapturingLogger in
//            return self.logger
//        }
//
//        config.prefer(ThrowingViewRenderer.self, for: ViewRenderer.self)
//        config.prefer(CapturingLogger.self, for: Logger.self)
        app.views.use { _ in
            return self.viewRenderer
        }

        func routes(_ router: RoutesBuilder) throws {

            router.get("ok") { req in
                return "ok"
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
    
    func testThatFuture404IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/future404")
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
}

extension Application {
    func getResponse(to path: String) throws -> Response {
        let request = Request(application: self, method: .GET, url: URI(path: path), on: self.eventLoopGroup.next())
        return try self.responder.respond(to: request).wait()
    }
}
