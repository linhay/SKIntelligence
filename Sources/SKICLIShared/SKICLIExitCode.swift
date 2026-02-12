import Foundation
import SKIACPClient
import SKIACPTransport

public enum SKICLIExitCode: Int, Sendable {
    case success = 0
    case invalidInput = 2
    case configurationError = 3
    case upstreamFailure = 4
    case internalError = 5
}

public enum SKICLIExitCodeMapper {
    public static func exitCode(for error: Error) -> SKICLIExitCode {
        if error is SKICLIValidationError {
            return .invalidInput
        }
        if error is ACPClientServiceError || error is ACPTransportError || error is URLError {
            return .upstreamFailure
        }
        return .internalError
    }
}
