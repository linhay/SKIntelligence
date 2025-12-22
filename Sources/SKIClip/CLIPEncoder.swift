//
//  CLIPEncoder.swift
//  SKIntelligence
//
//  Created by linhey on 7/11/25.
//

import CoreML
import Foundation

public protocol CLIPEncoder: Sendable {
    var id: String { get }
    var name: String { get }
    var targetImageSize: CGSize { get }
    func unlinkImageEncoderModel() async throws
    func unlinkTextEncoderModel() async throws
    func encode(image: CVPixelBuffer) async throws -> MLMultiArray
    func encode(text: MLMultiArray) async throws -> MLMultiArray
}


import CoreImage
import QuartzCore

/// shared tokenizer for all model types
private let tokenizer = AsyncFactory {
    CLIPTokenizer()
}

public extension CLIPEncoder {
    
    // Compute Text Embeddings
    func embedding(text: String) async throws -> MLMultiArray {
        print("Prompt text: \(text)")
        let inputIds = await tokenizer.get().encode_full(text: text)
        let inputArray = try MLMultiArray(shape: [1, 77], dataType: .int32)
        for (index, element) in inputIds.enumerated() {
            inputArray[index] = NSNumber(value: element)
        }
        return try await encode(text: inputArray)
    }

    
}

public extension CLIPEncoder {

    func embedding(
        image frame: CVPixelBuffer,
        context: CIContext
    ) async throws -> MLMultiArray? {
        try await embedding(image: CIImage(cvPixelBuffer: frame), context: context)
    }
    
    func embedding(
        image: CIImage,
        context: CIContext
    ) async throws -> MLMultiArray? {
        guard let image = image.cropToSquare()?.resize(size: targetImageSize) else { return nil }
        
        // output buffer
        let extent = image.extent
        let pixelFormat = kCVPixelFormatType_32ARGB
        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(extent.width), Int(extent.height), pixelFormat, nil, &output)
        
        guard let output else {
            print("[\(id)] failed to create output CVPixelBuffer")
            return nil
        }
        
        context.render(image, to: output)
        return try await encode(image: output)
    }

    
}
