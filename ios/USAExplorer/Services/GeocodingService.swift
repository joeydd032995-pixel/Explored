import Foundation
import CoreLocation

final class GeocodingService {
    private let geocoder = CLGeocoder()

    nonisolated struct Result: Sendable {
        let state: String?
        let county: String?
        let city: String?
    }

    func reverseGeocode(_ location: CLLocation) async -> Result? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return Result(
                state: placemark.administrativeArea,
                county: placemark.subAdministrativeArea,
                city: placemark.locality
            )
        } catch {
            return nil
        }
    }
}
