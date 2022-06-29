import LeafErrorMiddleware
@testable import Logging
import Vapor
import XCTest

class CustomMappingDefaultGeneratorTests: XCTestCase {
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
            
            router.get("404") { _ -> HTTPStatus in
                throw Abort(.notFound)
            }

            router.get("403") { _ -> Response in
                throw Abort(.forbidden)
            }
            
            router.get("303") { _ -> Response in
                throw Abort.redirect(to: "ok")
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

            router.get("401withReason") { _ -> HTTPStatus in
                throw Abort(.unauthorized, reason: "You need to log in")
            }

        }

        try routes(app)

        app.middleware.use(LeafErrorMiddlewareDefaultGenerator.build(errorMappings: [
            .notFound: "404",
            .unauthorized: "401",
            .forbidden: "403",
            // Verify that non-error mappings are ignored
            .seeOther: "303"
        ]))
    }

    override func tearDownWithError() throws {
        app.shutdown()
        try eventLoopGroup.syncShutdownGracefully()
    }

    // MARK: - Tests

    func testThatRedirectIsNotCaught() throws {
        let response = try app.getResponse(to: "/303")
        XCTAssertEqual(response.status, .seeOther)
        XCTAssertEqual(response.headers[.location].first, "ok")
        XCTAssertNotEqual(viewRenderer.leafPath, "303")
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

    func testThatUnauthorisedIsPassedThroughToCustomPage() throws {
        let response = try app.getResponse(to: "/unauthorized")
        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(viewRenderer.leafPath, "401")
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

    func testThat403IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/403")
        XCTAssertEqual(response.status, .forbidden)
        XCTAssertEqual(viewRenderer.leafPath, "403")
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
    
    func testReasonIsPassedThroughTo401Page() throws {
        let response = try app.getResponse(to: "/401withReason")
        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(viewRenderer.leafPath, "401")
        guard let context = viewRenderer.capturedContext as? DefaultContext else {
            XCTFail()
            return
        }
        XCTAssertEqual(context.reason, "You need to log in")
    }
}

