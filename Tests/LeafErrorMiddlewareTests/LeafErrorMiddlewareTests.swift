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

        viewRenderer = ThrowingViewRenderer()
        logger = CapturingLogger()

        config.prefer(ThrowingViewRenderer.self, for: TemplateRenderer.self)

//        try services.register(ThrowingViewRenderer())

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
            return try! LeafErrorMiddleware(environment: worker.environment, log: worker.make())
        }

        var middlewares = MiddlewareConfig()
        middlewares.use(LeafErrorMiddleware.self)
        services.register(middlewares)

        app = try! Application(config: config, environment: .xcode, services: services)
        try! app.asyncRun().wait()
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
        try app.clientTest(.GET, "/ok", equals: "ok")
    }
    
    func testThatRequestingInvalidEndpointReturns404View() throws {
        try app.clientTest(.GET, "/unknown") { res in
            XCTAssertEqual(res.http.status, .notFound)
            XCTAssertEqual(viewRenderer.leafPath, "404")
        }
    }
    
    func testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView() throws {
        try app.clientTest(.GET, "/serverError") { res in
            XCTAssertEqual(res.http.status, .internalServerError)
            XCTAssertEqual(viewRenderer.leafPath, "serverError")
        }
    }
    
    func testThatErrorGetsLogged() throws {
        try app.clientTest(.GET, "/serverError") { res in
            XCTAssertNotNil(logger.message)
            XCTAssertEqual(logger.logLevel!, LogLevel.error)
        }
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFails() throws {
        viewRenderer.shouldThrow = true
        try app.clientTest(.GET, "/serverError") { res in
            XCTAssertEqual(res.http.status, .internalServerError)
            XCTAssertEqual(res.http.body.string, "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
        }
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFailsFor404() throws {
        viewRenderer.shouldThrow = true
        try app.clientTest(.GET, "/unknown") { res in
            XCTAssertEqual(res.http.status, .notFound)
            XCTAssertEqual(res.http.body.string, "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
        }
    }
    
    func testThatRandomErrorGetsReturnedAsServerError() throws {
        try app.clientTest(.GET, "/unknownError") { res in
            XCTAssertEqual(res.http.status, .internalServerError)
            XCTAssertEqual(viewRenderer.leafPath, "serverError")
        }
    }
    
    func testThatUnauthorisedIsPassedThroughToServerErrorPage() throws {
        try app.clientTest(.GET, "/unauthorized") { res in
            XCTAssertEqual(res.http.status, .unauthorized)
            XCTAssertEqual(viewRenderer.leafPath, "serverError")
            XCTAssertEqual(viewRenderer.capturedContext?["status"], "401")
            XCTAssertEqual(viewRenderer.capturedContext?["statusMessage"], "Unauthorized")
        }
    }
}

extension HTTPBody {
    var string: String {
        guard let data = self.data else {
            return "<streaming>"
        }
        return String(data: data, encoding: .ascii) ?? "<non-ascii>"
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
