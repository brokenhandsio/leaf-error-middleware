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
        ("testThatMiddlewareFallsBackIfViewRendererFailsFor404", testThatMiddlewareFallsBackIfViewRendererFailsFor404),
        ("testThatRandomErrorGetsReturnedAsServerError", testThatRandomErrorGetsReturnedAsServerError),
        ("testThatUnauthorisedIsPassedThroughToServerErrorPage", testThatUnauthorisedIsPassedThroughToServerErrorPage),
    ]
    
    // MARK: - Properties
    var drop: Droplet!
    var viewRenderer: ThrowingViewRenderer!
    var logger: CapturingLogger!
    
    // MARK: - Overrides
    override func setUp() {
        var config = Config([:])
        viewRenderer = ThrowingViewRenderer()
        logger = CapturingLogger()
        config.addConfigurable(middleware: LeafErrorMiddleware.init, name: "leaf-error")
        config.addConfigurable(view: { (_) -> (ThrowingViewRenderer) in
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
        
        drop.get("unauthorized") { req in
            throw Abort.unauthorized
        }
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
    
    func testThatMiddlewareFallsBackIfViewRendererFailsFor404() throws {
        viewRenderer.shouldThrow = true
        let response = try drop.respond(to: Request(method: .get, uri: "/unknown"))
        
        XCTAssertEqual(response.status, .notFound)
        XCTAssertEqual(response.body.bytes?.makeString(), "<h1>Internal Error</h1><p>There was an internal error. Please try again later.</p>")
    }
    
    func testThatRandomErrorGetsReturnedAsServerError() throws {
        let response = try drop.respond(to: Request(method: .get, uri: "/unknownError"))
        
        XCTAssertEqual(response.status, .internalServerError)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
    }
    
    func testThatUnauthorisedIsPassedThroughToServerErrorPage() throws {
        let response = try drop.respond(to: Request(method: .get, uri: "/unauthorized"))
        
        XCTAssertEqual(response.status, .unauthorized)
        XCTAssertEqual(viewRenderer.leafPath, "serverError")
        XCTAssertEqual(viewRenderer.capturedContext?["status"]?.string, "401")
        XCTAssertEqual(viewRenderer.capturedContext?["statusMessage"]?.string, "Unauthorized")
    }
}
