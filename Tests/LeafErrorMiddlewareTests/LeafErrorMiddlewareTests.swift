import XCTest
import LeafErrorMiddleware
@testable import Vapor

class LeafErrorMiddlewareTests: XCTestCase {
    
    // MARK: - All tests
    static var allTests = [
        ("testLinuxTestSuiteIncludesAllTests", testLinuxTestSuiteIncludesAllTests),
        ("testThatValidEndpointWorks", testThatValidEndpointWorks),
        ("testThatRequestingInvalidEndpointReturns404View", testThatRequestingInvalidEndpointReturns404View),
        ("testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView", testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView),
        ("testThatErrorGetsLogged", testThatErrorGetsLogged),
        ("testThatMiddlewareFallsBackIfViewRendererFails", testThatMiddlewareFallsBackIfViewRendererFails),
        ("testThatMiddlewareFallsBackIfViewRendererFailsFor404", testThatMiddlewareFallsBackIfViewRendererFailsFor404),
        ("testMessageLoggedIfRendererThrows", testMessageLoggedIfRendererThrows),
        ("testThatRandomErrorGetsReturnedAsServerError", testThatRandomErrorGetsReturnedAsServerError),
        ("testThatUnauthorisedIsPassedThroughToServerErrorPage", testThatUnauthorisedIsPassedThroughToServerErrorPage),
        ("testThatFuture404IsCaughtCorrectly", testThatFuture404IsCaughtCorrectly),
        ("testThatFuture403IsCaughtCorrectly", testThatFuture403IsCaughtCorrectly),
        ("testThatRedirectIsNotCaught", testThatRedirectIsNotCaught)
    ]
    
    // MARK: - Properties
    var app: Application!
    var viewRenderer: ThrowingViewRenderer!
    var logger: CapturingLogger!
    
    // MARK: - Overrides
    override func setUp() {
        var config = Config.default()
        var services = Services.default()

        let worker = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        viewRenderer = ThrowingViewRenderer(worker: worker)
        logger = CapturingLogger()

        services.register(ViewRenderer.self) { container -> ThrowingViewRenderer in
            return self.viewRenderer
        }
        services.register(Logger.self) { container -> CapturingLogger in
            return self.logger
        }

        config.prefer(ThrowingViewRenderer.self, for: ViewRenderer.self)
        config.prefer(CapturingLogger.self, for: Logger.self)

        func routes(_ router: Router) throws {

            router.get("ok") { req in
                return "ok"
            }

            router.get("serverError") { req -> Future<Response> in
                throw Abort(.internalServerError)
            }

            router.get("unknownError") { req -> Future<Response> in
                throw TestError()
            }

            router.get("unauthorized") { req -> Future<Response> in
                throw Abort(.unauthorized)
            }
            
            router.get("future404") { req -> Future<Response> in
                return req.future(error: Abort(.notFound))
            }
            
            router.get("future403") { req -> Future<Response> in
                return req.future(error: Abort(.forbidden))
            }

            router.get("future303") { req -> Future<Response> in
                return req.future(error: Abort.redirect(to: "ok"))
            }
        }

        let router = EngineRouter.default()
        try! routes(router)
        services.register(router, as: Router.self)

        services.register { worker in
            return LeafErrorMiddleware(environment: worker.environment)
        }

        var middlewares = MiddlewareConfig()
        middlewares.use(LeafErrorMiddleware.self)
        services.register(middlewares)

        app = try! Application(config: config, services: services)
    }
    
    // MARK: - Tests
    func testLinuxTestSuiteIncludesAllTests() {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let thisClass = type(of: self)
            let linuxCount = thisClass.allTests.count
            let darwinCount = Int(thisClass
                .defaultTestSuite.testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from allTests")
        #endif
    }
    
    func testThatValidEndpointWorks() throws {
        let response = try app.getResponse(to: "/ok")
        XCTAssertEqual(response.http.status, .ok)
    }
    
    func testThatRequestingInvalidEndpointReturns404View() throws {
        let response = try app.getResponse(to: "/unknown")
        XCTAssertEqual(response.http.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView() throws {
        let response = try app.getResponse(to: "/serverError")
        XCTAssertEqual(response.http.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    func testThatErrorGetsLogged() throws {
        _ = try app.getResponse(to: "/serverError")
        XCTAssertNotNil(logger.message)
        XCTAssertEqual(logger.logLevel!, LogLevel.error)
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFails() throws {
        viewRenderer.shouldThrow = true
        let response = try app.getResponse(to: "/serverError")
        XCTAssertEqual(response.http.status, .internalServerError)
        XCTAssertEqual(response.http.body.string, "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFailsFor404() throws {
        viewRenderer.shouldThrow = true
        let response = try app.getResponse(to: "/unknown")
        XCTAssertEqual(response.http.status, .notFound)
        XCTAssertEqual(response.http.body.string, "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
    }

    func testMessageLoggedIfRendererThrows() throws {
        viewRenderer.shouldThrow = true
        _ = try app.getResponse(to: "/serverError")
        XCTAssertTrue(logger.message?.starts(with: "Failed to render custom error page") ?? false)
    }
    
    func testThatRandomErrorGetsReturnedAsServerError() throws {
        let response = try app.getResponse(to: "/unknownError")
        XCTAssertEqual(response.http.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    func testThatUnauthorisedIsPassedThroughToServerErrorPage() throws {
        let response = try app.getResponse(to: "/unauthorized")
        XCTAssertEqual(response.http.status, .unauthorized)
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
        XCTAssertEqual(response.http.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testThatFuture403IsCaughtCorrectly() throws {
        let response = try app.getResponse(to: "/future403")
        XCTAssertEqual(response.http.status, .forbidden)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }

    func testThatRedirectIsNotCaught() throws {
        let response = try app.getResponse(to: "/future303")
        XCTAssertEqual(response.http.status, .seeOther)
        XCTAssertEqual(response.http.headers[.location].first, "ok")
    }
}

extension HTTPBody {
    var string: String {
        return String(data: data!, encoding: .utf8)!
    }
}

extension Application {
    func getResponse(to path: String) throws -> Response {
        let responder = try self.make(Responder.self)
        let request = HTTPRequest(method: .GET, url: URL(string: path)!)
        let wrappedRequest = Request(http: request, using: self)
        return try responder.respond(to: wrappedRequest).wait()
    }
}

extension LogLevel: Equatable {
    public static func == (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.description == rhs.description
    }
}
