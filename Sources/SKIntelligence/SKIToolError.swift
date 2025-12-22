//
//  SKIToolError.swift
//  SKIntelligence
//
//  Created by linhey on 2025.
//

import Foundation

/// Unified error type for all SKI tools.
/// This provides consistent error handling across all tool implementations.
public enum SKIToolError: Error, LocalizedError, Sendable {
    
    // MARK: - Network Errors
    
    /// The request timed out
    case timeout(TimeInterval)
    
    /// Network connection failed
    case networkUnavailable
    
    /// Server returned an error status code
    case serverError(statusCode: Int, message: String?)
    
    /// Failed to decode the response
    case decodingFailed(Error)
    
    /// Invalid URL provided
    case invalidURL(String)
    
    // MARK: - Authentication Errors
    
    /// Authentication failed or token is invalid
    case authenticationFailed
    
    /// API rate limit exceeded
    case rateLimitExceeded(retryAfter: TimeInterval?)
    
    // MARK: - Tool Execution Errors
    
    /// The tool is not available
    case toolUnavailable(name: String)
    
    /// Invalid arguments provided to the tool
    case invalidArguments(String)
    
    /// Tool execution failed with a specific reason
    case executionFailed(reason: String)
    
    // MARK: - Permission Errors
    
    /// Required permission was denied
    case permissionDenied(String)
    
    // MARK: - Retry Errors
    
    /// All retry attempts exhausted
    case retryExhausted(attempts: Int, lastError: Error)
    
    /// Operation was cancelled
    case cancelled
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .timeout(let interval):
            return "Request timed out after \(Int(interval)) seconds"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .serverError(let code, let message):
            if let message = message {
                return "Server error (\(code)): \(message)"
            }
            return "Server error with status code: \(code)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .authenticationFailed:
            return "Authentication failed"
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Retry after \(Int(retryAfter)) seconds"
            }
            return "Rate limit exceeded"
        case .toolUnavailable(let name):
            return "Tool '\(name)' is not available"
        case .invalidArguments(let reason):
            return "Invalid arguments: \(reason)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission)"
        case .retryExhausted(let attempts, let lastError):
            return "All \(attempts) retry attempts failed. Last error: \(lastError.localizedDescription)"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
    
    // MARK: - JSON Representation for Model
    
    /// Returns a JSON-formatted error message suitable for returning to a language model.
    public var jsonDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        
        struct ErrorInfo: Encodable {
            let error: String
            let code: String
            let message: String
        }
        
        let info = ErrorInfo(
            error: "SKIToolError",
            code: errorCode,
            message: errorDescription ?? "Unknown error"
        )
        
        if let data = try? encoder.encode(info),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "{\"error\": \"SKIToolError\", \"message\": \"\(errorDescription ?? "Unknown error")\"}"
    }
    
    private var errorCode: String {
        switch self {
        case .timeout: return "TIMEOUT"
        case .networkUnavailable: return "NETWORK_UNAVAILABLE"
        case .serverError: return "SERVER_ERROR"
        case .decodingFailed: return "DECODING_FAILED"
        case .invalidURL: return "INVALID_URL"
        case .authenticationFailed: return "AUTH_FAILED"
        case .rateLimitExceeded: return "RATE_LIMITED"
        case .toolUnavailable: return "TOOL_UNAVAILABLE"
        case .invalidArguments: return "INVALID_ARGUMENTS"
        case .executionFailed: return "EXECUTION_FAILED"
        case .permissionDenied: return "PERMISSION_DENIED"
        case .retryExhausted: return "RETRY_EXHAUSTED"
        case .cancelled: return "CANCELLED"
        }
    }
}

// MARK: - Retryable Error Check

extension SKIToolError {
    
    /// Whether this error should trigger a retry attempt
    public var isRetryable: Bool {
        switch self {
        case .timeout, .networkUnavailable:
            return true
        case .serverError(let code, _):
            // Retry on 5xx errors and 429 (rate limit)
            return code >= 500 || code == 429
        case .rateLimitExceeded:
            return true
        default:
            return false
        }
    }
}
