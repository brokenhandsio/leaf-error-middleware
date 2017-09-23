import XCTest
import LeafErrorMiddleware
import Vapor

class LeafErrorMiddlewareTests: XCTestCase {
    
    // MARK: - All tests
    static var allTests = [
        ("testLinuxTestSuiteIncludesAllTests", testLinuxTestSuiteIncludesAllTests),
        ("testThatValidEndpointWorks", testThatValidEndpointWorks),
        ("testThatRequestingInvalidEndpointReturns404View", testThatRequestingInvalidEndpointReturns404View),
        ("testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView", testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView),
        ("testThatErrorGetsLogged", testThatErrorGetsLogged),
        ("testThatMiddlewareFallsBackIfViewRendererFails", testThatMiddlewareFallsBackIfViewRendererFails),
        ("testThatRandomErrorGetsReturnedAsServerError", testThatRandomErrorGetsReturnedAsServerError),
    ]
    
    // MARK: - Properties
    var drop: Droplet!
    var viewRenderer: ConfigurableViewRenderer!
    var logger: CapturingLogger!
    
    // MARK: - Overrides
    override func setUp() {
        var config = Config([:])
        viewRenderer = ConfigurableViewRenderer()
        logger = CapturingLogger()
        config.addConfigurable(middleware: LeafErrorMiddleware.init, name: "leaf-error")
        config.addConfigurable(view: { (_) -> (ConfigurableViewRenderer) in
            return self.viewRenderer
        }, name: "configurable")
        config.addConfigurable(log: { (_) -> (CapturingLogger) in
            return self.logger
        }, name: "capturing")
        try! config.set("droplet.middleware", ["leaf-error"])
        try! config.set("droplet.view", "configurable")
        try! config.set("droplet.log", "capturing")
        
        drop = try! Droplet(config)
        
        drop.get("ok") { req in
            return "OK"
        }
        
        drop.get("serverError") { req in
            throw Abort.serverError
        }
        
        drop.get("unknownError") { req in
            throw TestError()
        }
    }
    
    // MARK: - Tests
    func testLinuxTestSuiteIncludesAllTests() {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let thisClass = type(of: self)
            let linuxCount = thisClass.allTests.count
            let darwinCount = Int(thisClass
                .defaultTestSuite.testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount,
                           "\(darwinCount - linuxCount) tests are missing from allTests")
        #endif
    }
    
    func testThatValidEndpointWorks() throws {
        let response = try drop.respond(to: Request(method: .get, uri: "/ok"))
        
        XCTAssertEqual(response.status, .ok)
    }
    
    func testThatRequestingInvalidEndpointReturns404View() throws {
        let response = try drop.respond(to: Request(method: .get, uri: "/unknown"))
        
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(viewRenderer.leafPath, "404")
    }
    
    func testThatRequestingPageThatCausesAServerErrorReturnsServerErrorView() throws {
        let response = try drop.respond(to: Request(method: .get, uri: "/serverError"))
        
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    func testThatErrorGetsLogged() throws {
        _ = try drop.respond(to: Request(method: .get, uri: "/serverError"))
        
        XCTAssertNotNil(logger.message)
        XCTAssertEqual(logger.logLevel, .error)
    }
    
    func testThatMiddlewareFallsBackIfViewRendererFails() throws {
        viewRenderer.shouldThrow = true
        let response = try drop.respond(to: Request(method: .get, uri: "/serverError"))
        
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(response.body.bytes?.makeString(), "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
    }
    
    func testThatRandomErrorGetsReturnedAsServerError() throws {
        let response = try drop.respond(to: Request(method: .get, uri: "/unknownError"))
        
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    class ConfigurableViewRenderer: ViewRenderer {
        
        var shouldCache = false
        var shouldThrow = false
        
        private(set) var capturedContext: Node? = nil
        private(set) var leafPath: String? = nil
        func make(_ path: String, _ context: Node) throws -> View {
            if shouldThrow {
                throw TestError()
            }
            self.capturedContext = context
            self.leafPath = path
            return View(data: "Test".makeBytes())
        }
    }
    
    class CapturingLogger: LogProtocol {
        var enabled: [LogLevel] = []
        
        private(set) var message: String?
        private(set) var logLevel: LogLevel?
        func log(_ level: LogLevel, message: String, file: String, function: String, line: Int) {
            self.message = message
            self.logLevel = level
        }
    }
    
    struct TestError: Error {}
}
