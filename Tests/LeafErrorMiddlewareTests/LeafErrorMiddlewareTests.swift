import XCTest
import LeafErrorMiddleware
@testable import Vapor

class LeafErrorMiddlewareTests: XCTestCase {
        
    // MARK: - Properties
    var app: Application!
    var viewRenderer: ThrowingViewRenderer!
    var logger: CapturingLogger!
    
    // MARK: - Overrides
    override func setUp() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        viewRenderer = ThrowingViewRenderer(eventLoop: eventLoopGroup.next())
        logger = CapturingLogger()

//        services.register(ViewRenderer.self) { container -> ThrowingViewRenderer in
//            return self.viewRenderer
//        }
//        services.register(Logger.self) { container -> CapturingLogger in
//            return self.logger
//        }
//
//        config.prefer(ThrowingViewRenderer.self, for: ViewRenderer.self)
//        config.prefer(CapturingLogger.self, for: Logger.self)

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

//        let router = EngineRouter.default()
//        try! routes(router)
//        services.register(router, as: Router.self)

//        services.register { worker in
//            return LeafErrorMiddleware(environment: worker.environment)
//        }

//        var middlewares = MiddlewareConfig()
//        middlewares.use(LeafErrorMiddleware.self)
//        services.register(middlewares)
//
//        app = try! Application(config: config, services: services)
    }
    
    override func tearDownWithError() throws {
        app.shutdown()
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

//extension HTTPBody {
//    var string: String {
//        return String(data: data!, encoding: .utf8)!
//    }
//}

extension Application {
    func getResponse(to path: String) throws -> Response {
//        let responder = try self.make(Responder.self)
//        let request = HTTPRequest(method: .GET, url: URL(string: path)!)
//        let wrappedRequest = Request(http: request, using: self)
//        return try responder.respond(to: wrappedRequest).wait()
        fatalError()
    }
}

//extension Logger.Level: Equatable {
//    public static func == (lhs: LogLevel, rhs: LogLevel) -> Bool {
//        return lhs.description == rhs.description
//    }
//}
