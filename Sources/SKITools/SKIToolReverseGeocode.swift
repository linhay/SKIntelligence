//
//  SKIToolReverseGeocode.swift
//  SKIntelligence
//
//  Created by linhey on 6/15/25.
//

#if canImport(CoreLocation)
    import Foundation
    import CoreLocation
    import SKIntelligence
    import JSONSchemaBuilder

    public struct SKIToolReverseGeocode: SKITool {

        @Schemable
        public struct Arguments {
            @SchemaOptions(.description("纬度"))
            public let latitude: Double

            @SchemaOptions(.description("经度"))
            public let longitude: Double

            public init(latitude: Double, longitude: Double) {
                self.latitude = latitude
                self.longitude = longitude
            }
        }

        @Schemable
        public struct ToolOutput: Codable, Sendable {
            @SchemaOptions(.description("地址信息"))
            public let address: String?

            @SchemaOptions(.description("可能的错误信息"))
            public let error: String?

            public init(address: String? = nil, error: String? = nil) {
                self.address = address
                self.error = error
            }
        }

        public let name: String = "reverseGeocode"
        public let description: String = "根据经纬度获取对应的地址信息。"

        public init() {}

        public func call(_ arguments: Arguments) async throws -> ToolOutput {
            let location = CLLocation(latitude: arguments.latitude, longitude: arguments.longitude)
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return ToolOutput(error: "无法获取地址信息")
            }

            let address = [
                placemark.name,
                placemark.thoroughfare,
                placemark.locality,
                placemark.administrativeArea,
                placemark.country,
            ].compactMap { $0 }.joined(separator: ", ")
            return ToolOutput(address: address)
        }
    }

#endif
