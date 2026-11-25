import Foundation
import CoreLocation

nonisolated struct StoredCoordinate: Sendable {
    let id: Int64
    let latitude: Double
    let longitude: Double
    let timestamp: Int64

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
