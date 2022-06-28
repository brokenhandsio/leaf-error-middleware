import Vapor

public enum LeafErrorMiddlewareDefaultGenerator {
    static func generate(_ status: HTTPStatus, _ error: Error, _ req: Request) async throws -> DefaultContext {
        let reason: String?
        if let abortError = error as? AbortError {
            reason = abortError.reason
        } else {
            reason = nil
        }
        let context = DefaultContext(status: status.code.description, statusMessage: status.reasonPhrase, reason: reason)
        return context
    }

    public static func build() -> LeafErrorMiddleware<DefaultContext> {
        LeafErrorMiddleware(contextGenerator: generate)
    }
    
    public static func build(errorMappings: [HTTPStatus: String]) -> LeafErrorMiddleware<DefaultContext> {
        LeafErrorMiddleware(errorMappings: errorMappings, contextGenerator: generate)
    }
}
