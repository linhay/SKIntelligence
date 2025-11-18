//
//  SKIToolLocalLocation.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

import Foundation
import SKIntelligence
import JSONSchemaBuilder
import CoreLocation

public struct SKIToolLocalLocation: SKITool {

    @Schemable
    public struct Arguments: Sendable {
        @SchemaOptions(.description("是否包含详细地址信息"))
        public let includeAddress: Bool?
        
        @SchemaOptions(.description("坐标精度，默认为最佳精度"))
        public let desiredAccuracy: Double?

        public init(includeAddress: Bool? = nil, desiredAccuracy: Double? = nil) {
            self.includeAddress = includeAddress
            self.desiredAccuracy = desiredAccuracy
        }
    }

    @Schemable
    public struct ToolOutput: Codable, Sendable {
        @SchemaOptions(.description("纬度"))
        public let latitude: Double?
        
        @SchemaOptions(.description("经度"))
        public let longitude: Double?
        
        @SchemaOptions(.description("精度（以米为单位）"))
        public let accuracy: Double?
        
        @SchemaOptions(.description("地址信息（如果请求）"))
        public let address: String?
        
        @SchemaOptions(.description("可能的错误信息"))
        public let error: String?

        public init(latitude: Double? = nil,
                   longitude: Double? = nil,
                   accuracy: Double? = nil,
                   address: String? = nil,
                   error: String? = nil) {
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
            self.address = address
            self.error = error
        }
    }

    public let name: String = "getCurrentLocation"
    public var shortDescription: String = "获取当前地理位置"
    public let description: String = "返回当前地理位置的经纬度坐标，可选返回详细地址信息。"
    private let coordinate = LocationCoordinate()
    private let reverseGeocode = SKIToolReverseGeocode()
        
    public init() {}

    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        let location = try await withUnsafeThrowingContinuation { continuation in
            coordinate.current(desiredAccuracy: arguments.desiredAccuracy.flatMap(CLLocationAccuracy.init), completion: { result in
                do {
                    continuation.resume(returning: try result.get())
                } catch {
                    continuation.resume(throwing: error)
                }
            })
        }
        if arguments.includeAddress ?? false {
            let address = try await reverseGeocode.call(.init(latitude: location.coordinate.latitude,
                                                              longitude: location.coordinate.longitude)).address
            return ToolOutput(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                address: address,
                error: nil
            )
        } else {
            return ToolOutput(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                address: nil,
                error: nil
            )
        }
    }

}

enum LocationError: Error {
    case denied
    case unavailable
    case timeout
    case geocodingFailed
}

class LocationCoordinate: NSObject, CLLocationManagerDelegate {
    
    private var locationManager = CLLocationManager()
    private var completion: ((Result<CLLocation, Error>) -> Void)?
    
    override init() {
        super.init()
        self.locationManager.delegate = self
    }
    
    func current(desiredAccuracy: CLLocationAccuracy? = nil,
                 completion: @escaping (Result<CLLocation, Error>) -> Void) {
        locationManager.desiredAccuracy = desiredAccuracy ?? .zero
        self.completion = completion
        let authStatus = locationManager.authorizationStatus
        switch authStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            self.locationManager.startUpdatingLocation()
        case .notDetermined:
            self.locationManager.requestWhenInUseAuthorization()
        default:
            self.completion?(.failure(LocationError.denied))
            self.completion = nil
        }
    }
        
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        completion?(.success(location))
        completion = nil
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(error))
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if completion != nil {
                self.locationManager.startUpdatingLocation()
            }
        case .denied, .restricted:
            self.completion?(.failure(LocationError.denied))
            self.completion = nil
        default:
            break
        }
    }
}
