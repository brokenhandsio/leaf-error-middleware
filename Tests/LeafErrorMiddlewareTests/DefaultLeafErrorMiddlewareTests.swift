import LeafErrorMiddleware
@testable import Logging
import Vapor
import XCTest

class DefaultLeafErrorMiddlewareTests: XCTestCase {
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
            self.logger
        }
        app = Application(.testing, .shared(eventLoopGroup))

        app.views.use { _ in
            self.viewRenderer
        }

        func routes(_ router: RoutesBuilder) throws {
            router.get("ok") { _ in
                "ok"
            }

            router.get("404") { _ -> HTTPStatus in
                .notFound
            }

            router.get("serverError") { _ -> Response in
                throw Abort(.internalServerError)
            }

            router.get("unknownError") { _ -> Response in
                throw TestError()
            }

            router.get("unauthorized") { _ -> Response in
                throw Abort(.unauthorized)
            }

            router.get("404withReason") { _ -> HTTPStatus in
                throw Abort(.notFound, reason: "Could not find it")
            }

            router.get("500withReason") { _ -> HTTPStatus in
                throw Abort(.badGateway, reason: "I messed up")
            }
        }

        try routes(app)

        app.middleware.use(LeafErrorMiddlewareDefaultGenerator.build())
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
        guard let context = viewRenderer.capturedContext as? DefaultContext else {
            XCTFail()
            return
        }
        XCTAssertEqual(context.status, "401")
        XCTAssertEqual(context.statusMessage, "Unauthorized")
    }

    func testNonAbort404IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }

    func testAddingMiddlewareToRouteGroup() throws {
        app.shutdown()
        app = Application(.testing, .shared(eventLoopGroup))
        app.views.use { _ in
            self.viewRenderer
        }
        let middlewareGroup = app.grouped(LeafErrorMiddlewareDefaultGenerator.build())
        middlewareGroup.get("404") { _ async throws -> Response in
            throw Abort(.notFound)
        }
        middlewareGroup.get("ok") { _ in
            "OK"
        }
        let validResponse = try app.getResponse(to: "ok")
        XCTAssertEqual(validResponse.status, .ok)
        let response = try app.getResponse(to: "404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }

    func testReasonIsPassedThroughTo404Page() throws {
        let response = try app.getResponse(to: "/404withReason")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
        guard let context = viewRenderer.capturedContext as? DefaultContext else {
            XCTFail()
            return
        }
        XCTAssertEqual(context.reason, "Could not find it")
    }

    func testReasonIsPassedThroughTo500Page() throws {
        let response = try app.getResponse(to: "/500withReason")
        XCTAssertEqual(response.status, .badGateway)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
        guard let context = viewRenderer.capturedContext as? DefaultContext else {
            XCTFail()
            return
        }
        XCTAssertEqual(context.reason, "I messed up")
    }
}

extension Application {
    func getResponse(to path: String) throws -> Response {
        let request = Request(application: self, method: .GET, url: URI(path: path), on: eventLoopGroup.next())
        return try responder.respond(to: request).wait()
    }
}
