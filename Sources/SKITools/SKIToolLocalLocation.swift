//
//  SKIToolLocalLocation.swift
//  SKIntelligence
//
//  Created by linhey on 6/14/25.
//

#if canImport(CoreLocation)
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

            public init(
                latitude: Double? = nil,
                longitude: Double? = nil,
                accuracy: Double? = nil,
                address: String? = nil,
                error: String? = nil
            ) {
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
        private let reverseGeocode = SKIToolReverseGeocode()

        public init() {}

        public func call(_ arguments: Arguments) async throws -> ToolOutput {
            let location = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<CLLocation, Error>) in
                let coordinator = LocationCoordinator()
                coordinator.requestLocation(
                    desiredAccuracy: arguments.desiredAccuracy.flatMap(CLLocationAccuracy.init)
                ) { result in
                    switch result {
                    case .success(let location):
                        continuation.resume(returning: location)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            if arguments.includeAddress ?? false {
                let address = try await reverseGeocode.call(
                    .init(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude)
                ).address
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

    // MARK: - Location Errors

    public enum LocationError: Error, LocalizedError {
        case denied
        case unavailable
        case timeout
        case geocodingFailed
        case unknown(Error)

        public var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access denied"
            case .unavailable:
                return "Location services unavailable"
            case .timeout:
                return "Location request timed out"
            case .geocodingFailed:
                return "Geocoding failed"
            case .unknown(let error):
                return "Location error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Location Coordinator

    /// Thread-safe location coordinator that handles a single location request.
    /// Each instance should only be used for one request.
    private final class LocationCoordinator: NSObject, CLLocationManagerDelegate,
        @unchecked Sendable
    {

        private let locationManager: CLLocationManager
        private var completion: ((Result<CLLocation, Error>) -> Void)?
        private let lock = NSLock()
        private var hasCompleted = false

        override init() {
            self.locationManager = CLLocationManager()
            super.init()
            self.locationManager.delegate = self
        }

        func requestLocation(
            desiredAccuracy: CLLocationAccuracy? = nil,
            completion: @escaping (Result<CLLocation, Error>) -> Void
        ) {
            lock.lock()
            self.completion = completion
            lock.unlock()

            locationManager.desiredAccuracy = desiredAccuracy ?? kCLLocationAccuracyBest

            let authStatus = locationManager.authorizationStatus
            switch authStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.requestLocation()
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            default:
                completeOnce(with: .failure(LocationError.denied))
            }
        }

        private func completeOnce(with result: Result<CLLocation, Error>) {
            lock.lock()
            guard !hasCompleted, let completion = self.completion else {
                lock.unlock()
                return
            }
            hasCompleted = true
            self.completion = nil
            lock.unlock()

            completion(result)
        }

        // MARK: - CLLocationManagerDelegate

        func locationManager(
            _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
        ) {
            guard let location = locations.last else { return }
            completeOnce(with: .success(location))
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            completeOnce(with: .failure(LocationError.unknown(error)))
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                lock.lock()
                let hasPendingRequest = completion != nil && !hasCompleted
                lock.unlock()

                if hasPendingRequest {
                    manager.requestLocation()
                }
            case .denied, .restricted:
                completeOnce(with: .failure(LocationError.denied))
            default:
                break
            }
        }
    }

#endif
