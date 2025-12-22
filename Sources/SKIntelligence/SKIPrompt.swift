//
//  SKIPrompt.swift
//  SKIntelligence
//
//  Created by linhey on 6/13/25.
//

import Foundation

/// A user prompt that wraps `ChatRequestBody.Message` for convenient construction.
///
/// `SKIPrompt` provides a simplified API for creating user messages with text and/or images.
/// It can be initialized from string literals, built using result builders, or constructed
/// with explicit text and image content.
///
/// Example usage:
/// ```swift
/// // Simple text prompt
/// let prompt: SKIPrompt = "Hello, world!"
///
/// // Text with images
/// let prompt = SKIPrompt(text: "What's in this image?", images: [imageURL])
///
/// // Using builder
/// let prompt = SKIPrompt {
///     "First line"
///     "Second line"
/// }
/// ```
public struct SKIPrompt: Sendable {
    
    /// The underlying message representation
    public let message: ChatRequestBody.Message
    
    // MARK: - Computed Properties
    
    /// The text content of the prompt (if any)
    public var text: String? {
        switch message {
        case .user(let content, _):
            switch content {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.compactMap { part in
                    if case .text(let text) = part { return text }
                    return nil
                }.joined(separator: "\n")
            }
        default:
            return nil
        }
    }
    
    // MARK: - Initializers
    
    /// Creates a prompt from a `ChatRequestBody.Message`.
    public init(message: ChatRequestBody.Message) {
        self.message = message
    }
    
    /// Creates a text-only user prompt.
    public init(text: String, name: String? = nil) {
        self.message = .user(content: .text(text), name: name)
    }
    
    /// Creates a prompt with text and images.
    ///
    /// - Parameters:
    ///   - text: The text content of the prompt
    ///   - images: Array of image URLs (can be remote URLs or data URLs)
    ///   - imageDetail: The detail level for image processing
    ///   - name: Optional name for the participant
    public init(
        text: String,
        images: [URL],
        imageDetail: ChatRequestBody.Message.ContentPart.ImageDetail? = nil,
        name: String? = nil
    ) {
        var parts: [ChatRequestBody.Message.ContentPart] = [.text(text)]
        parts.append(contentsOf: images.map { .imageURL($0, detail: imageDetail) })
        self.message = .user(content: .parts(parts), name: name)
    }
    
    /// Creates a prompt with images only.
    ///
    /// - Parameters:
    ///   - images: Array of image URLs
    ///   - imageDetail: The detail level for image processing
    ///   - name: Optional name for the participant
    public init(
        images: [URL],
        imageDetail: ChatRequestBody.Message.ContentPart.ImageDetail? = nil,
        name: String? = nil
    ) {
        let parts = images.map { ChatRequestBody.Message.ContentPart.imageURL($0, detail: imageDetail) }
        self.message = .user(content: .parts(parts), name: name)
    }
    
    /// Creates a prompt with mixed content parts.
    ///
    /// - Parameters:
    ///   - parts: Array of content parts (text, images, etc.)
    ///   - name: Optional name for the participant
    public init(
        parts: [ChatRequestBody.Message.ContentPart],
        name: String? = nil
    ) {
        self.message = .user(content: .parts(parts), name: name)
    }
    
    /// Creates a system prompt.
    public static func system(_ text: String, name: String? = nil) -> SKIPrompt {
        SKIPrompt(message: .system(content: .text(text), name: name))
    }
    
    /// Creates a developer prompt (for o1 models).
    public static func developer(_ text: String, name: String? = nil) -> SKIPrompt {
        SKIPrompt(message: .developer(content: .text(text), name: name))
    }
}

// MARK: - ExpressibleByStringLiteral

extension SKIPrompt: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self.init(text: value)
    }
}

// MARK: - Result Builder

extension SKIPrompt {
    
    @resultBuilder
    public struct Builder {
        public static func buildBlock(_ components: String...) -> String {
            components.joined(separator: "\n")
        }

        public static func buildOptional(_ component: String?) -> String {
            component ?? ""
        }

        public static func buildEither(first component: String) -> String {
            component
        }

        public static func buildEither(second component: String) -> String {
            component
        }

        public static func buildArray(_ components: [String]) -> String {
            components.joined(separator: "\n")
        }

        public static func buildExpression(_ expression: String) -> String {
            expression
        }

        public static func buildExpression(_ expression: SKIPrompt) -> String {
            expression.text ?? ""
        }

        public static func buildLimitedAvailability(_ component: String) -> String {
            component
        }
    }

    /// Creates a prompt using a result builder.
    public init(@Builder _ content: () -> String) {
        self.init(text: content())
    }
}

// MARK: - Image Data Helpers

extension SKIPrompt {
    
    /// Creates a data URL from image data for use with vision models.
    ///
    /// - Parameters:
    ///   - data: The raw image data
    ///   - mimeType: The MIME type of the image (e.g., "image/jpeg", "image/png")
    /// - Returns: A data URL suitable for use with image prompts
    public static func imageDataURL(from data: Data, mimeType: String = "image/jpeg") -> URL? {
        let base64 = data.base64EncodedString()
        return URL(string: "data:\(mimeType);base64,\(base64)")
    }
    
    /// Creates a prompt with text and image data.
    ///
    /// - Parameters:
    ///   - text: The text content
    ///   - imageData: Array of tuples containing image data and MIME type
    ///   - imageDetail: The detail level for image processing
    ///   - name: Optional name for the participant
    public init(
        text: String,
        imageData: [(data: Data, mimeType: String)],
        imageDetail: ChatRequestBody.Message.ContentPart.ImageDetail? = nil,
        name: String? = nil
    ) {
        let imageURLs = imageData.compactMap { Self.imageDataURL(from: $0.data, mimeType: $0.mimeType) }
        self.init(text: text, images: imageURLs, imageDetail: imageDetail, name: name)
    }
}

// MARK: - Deprecated Compatibility

extension SKIPrompt {
    
    /// The text value of the prompt.
    /// - Note: Use `text` property instead for optional semantics.
    @available(*, deprecated, renamed: "text")
    public var value: String {
        text ?? ""
    }
}

