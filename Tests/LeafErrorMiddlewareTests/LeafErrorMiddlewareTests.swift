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
        ("testThatRandomErrorGetsReturnedAsServerError", testThatRandomErrorGetsReturnedAsServerError),
        ("testThatUnauthorisedIsPassedThroughToServerErrorPage", testThatUnauthorisedIsPassedThroughToServerErrorPage),
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

        config.prefer(ThrowingViewRenderer.self, for: ViewRenderer.self)

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

        app = try! Application(config: config, environment: .xcode, services: services)
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
//        XCTAssertEqual(logger.logLevel!, LogLevel.error)
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
}

extension HTTPBody {
    var string: String {
        return String(data: data!, encoding: .utf8)!
    }
}

extension Application {
    static func runningTest(port: Int, configure: (Router) throws -> ()) throws -> Application {
        let router = EngineRouter.default()
        try configure(router)
        var services = Services.default()
        services.register(router, as: Router.self)
        let serverConfig = EngineServerConfig(
            hostname: "localhost",
            port: port,
            backlog: 8,
            workerCount: 1,
            maxBodySize: 128_000,
            reuseAddress: true,
            tcpNoDelay: true
        )
        services.register(serverConfig)
        let app = try Application.asyncBoot(config: .default(), environment: .xcode, services: services).wait()
        try app.asyncRun().wait()
        return app
    }

    static func makeTest(configure: (Router) throws -> ()) throws -> Application {
        let router = EngineRouter.default()
        try configure(router)
        var services = Services.default()
        services.register(router, as: Router.self)
        return try Application.asyncBoot(config: .default(), environment: .xcode, services: services).wait()
    }
}

extension Application {
    func test(_ method: HTTPMethod, _ path: String, check: (Response) throws -> ()) throws {
        let http = HTTPRequest(method: method, url: URL(string: path)!)
        let req = Request(http: http, using: self)
        let res = try make(Responder.self).respond(to: req).wait()
        try check(res)
    }

    func clientTest(_ method: HTTPMethod, _ path: String, check: (Response) throws -> ()) throws {
        let config = try make(EngineServerConfig.self)
        let res = try FoundationClient.default(on: self).send(method, to: "http://localhost:\(config.port)" + path).wait()
        try check(res)
    }


    func clientTest(_ method: HTTPMethod, _ path: String, equals: String) throws {
        return try clientTest(method, path) { res in
            XCTAssertEqual(res.http.body.string, equals)
        }
    }

    func clientTest(_ method: HTTPMethod, _ path: String, equals: HTTPStatus) throws {
        return try clientTest(method, path) { res in
            XCTAssertEqual(res.http.status, equals)
        }
    }

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

extension Environment {
    static var xcode: Environment {
        return .init(name: "xcode", isRelease: false, arguments: ["xcode"])
    }
}
