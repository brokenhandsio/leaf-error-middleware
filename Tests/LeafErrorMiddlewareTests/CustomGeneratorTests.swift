import LeafErrorMiddleware
@testable import Logging
import Vapor
import XCTest

struct AContext: Encodable {
    let trigger: Bool
}

class CustomGeneratorTests: XCTestCase {
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

            router.get("403") { _ -> Response in
                throw Abort(.forbidden)
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

            router.get("303") { _ -> Response in
                throw Abort.redirect(to: "ok")
            }

            router.get("404withReason") { _ -> HTTPStatus in
                throw Abort(.notFound, reason: "Could not find it")
            }

            router.get("500withReason") { _ -> HTTPStatus in
                throw Abort(.badGateway, reason: "I messed up")
            }
        }

        try routes(app)

        let leafMiddleware = LeafErrorMiddleware { status, error, req async throws -> AContext in
            AContext(trigger: true)
        }
        app.middleware.use(leafMiddleware)
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

    func testThatRedirectIsNotCaught() throws {
        let response = try app.getResponse(to: "/303")
        XCTAssertEqual(response.status, .seeOther)
        XCTAssertEqual(response.headers[.location].first, "ok")
    }

    func testNonAbort404IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }

    func testThat403IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/403")
        XCTAssertEqual(response.status, .forbidden)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }

    func testContextGeneratedOn404Page() throws {
        let response = try app.getResponse(to: "/404")
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
        let context = try XCTUnwrap(viewRenderer.capturedContext as? AContext)
        XCTAssertTrue(context.trigger)
    }

    func testContextGeneratedOn500Page() throws {
        let response = try app.getResponse(to: "/unauthorized")
        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
        let context = try XCTUnwrap(viewRenderer.capturedContext as? AContext)
        XCTAssertTrue(context.trigger)
    }

    func testGetAResponseWhenGenerator() throws {
        app.shutdown()
        app = Application(.testing, .shared(eventLoopGroup))
        app.views.use { _ in
            self.viewRenderer
        }
        let leafErrorMiddleware = LeafErrorMiddleware { _, _, _ -> AContext in
            throw Abort(.internalServerError)
        }
        app.middleware = .init()
        app.middleware.use(leafErrorMiddleware)

        app.get("404") { _ async throws -> Response in
            throw Abort(.notFound)
        }
        app.get("500") { _ async throws -> Response in
            throw Abort(.internalServerError)
        }

        let response404 = try app.getResponse(to: "404")
        XCTAssertEqual(response404.status, .notFound)
        XCTAssertNil(viewRenderer.leafPath)

        let response500 = try app.getResponse(to: "500")
        XCTAssertEqual(response500.status, .internalServerError)
        XCTAssertNil(viewRenderer.leafPath)
    }
}
