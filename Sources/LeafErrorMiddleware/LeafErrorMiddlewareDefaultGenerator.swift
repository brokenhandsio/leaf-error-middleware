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

    public static func build(errorMappings: [HTTPStatus: String]? = nil) -> LeafErrorMiddleware<DefaultContext> {
        if let errorMappings = errorMappings {
            return LeafErrorMiddleware(errorMappings: errorMappings, contextGenerator: generate)
        }
        else {
            return LeafErrorMiddleware(contextGenerator: generate)
        }
    }
}
