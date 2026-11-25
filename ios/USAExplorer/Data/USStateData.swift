import Foundation

nonisolated struct USStateInfo: Sendable, Identifiable {
    let id: String
    let name: String
    let countyCount: Int
    let latitude: Double
    let longitude: Double
}

enum USStateData {
    nonisolated static let allStates: [USStateInfo] = [
        USStateInfo(id: "AL", name: "Alabama", countyCount: 67, latitude: 32.806671, longitude: -86.791130),
        USStateInfo(id: "AK", name: "Alaska", countyCount: 30, latitude: 61.370716, longitude: -152.404419),
        USStateInfo(id: "AZ", name: "Arizona", countyCount: 15, latitude: 33.729759, longitude: -111.431221),
        USStateInfo(id: "AR", name: "Arkansas", countyCount: 75, latitude: 34.969704, longitude: -92.373123),
        USStateInfo(id: "CA", name: "California", countyCount: 58, latitude: 36.116203, longitude: -119.681564),
        USStateInfo(id: "CO", name: "Colorado", countyCount: 64, latitude: 39.059811, longitude: -105.311104),
        USStateInfo(id: "CT", name: "Connecticut", countyCount: 8, latitude: 41.597782, longitude: -72.755371),
        USStateInfo(id: "DE", name: "Delaware", countyCount: 3, latitude: 39.318523, longitude: -75.507141),
        USStateInfo(id: "DC", name: "District of Columbia", countyCount: 1, latitude: 38.897438, longitude: -77.026817),
        USStateInfo(id: "FL", name: "Florida", countyCount: 67, latitude: 27.766279, longitude: -81.686783),
        USStateInfo(id: "GA", name: "Georgia", countyCount: 159, latitude: 33.040619, longitude: -83.643074),
        USStateInfo(id: "HI", name: "Hawaii", countyCount: 5, latitude: 21.094318, longitude: -157.498337),
        USStateInfo(id: "ID", name: "Idaho", countyCount: 44, latitude: 44.240459, longitude: -114.478828),
        USStateInfo(id: "IL", name: "Illinois", countyCount: 102, latitude: 40.349457, longitude: -88.986137),
        USStateInfo(id: "IN", name: "Indiana", countyCount: 92, latitude: 39.849426, longitude: -86.258278),
        USStateInfo(id: "IA", name: "Iowa", countyCount: 99, latitude: 42.011539, longitude: -93.210526),
        USStateInfo(id: "KS", name: "Kansas", countyCount: 105, latitude: 38.526600, longitude: -96.726486),
        USStateInfo(id: "KY", name: "Kentucky", countyCount: 120, latitude: 37.668140, longitude: -84.670067),
        USStateInfo(id: "LA", name: "Louisiana", countyCount: 64, latitude: 31.169546, longitude: -91.867805),
        USStateInfo(id: "ME", name: "Maine", countyCount: 16, latitude: 44.693947, longitude: -69.381927),
        USStateInfo(id: "MD", name: "Maryland", countyCount: 24, latitude: 39.063946, longitude: -76.802101),
        USStateInfo(id: "MA", name: "Massachusetts", countyCount: 14, latitude: 42.230171, longitude: -71.530106),
        USStateInfo(id: "MI", name: "Michigan", countyCount: 83, latitude: 43.326618, longitude: -84.536095),
        USStateInfo(id: "MN", name: "Minnesota", countyCount: 87, latitude: 45.694454, longitude: -93.900192),
        USStateInfo(id: "MS", name: "Mississippi", countyCount: 82, latitude: 32.741646, longitude: -89.678696),
        USStateInfo(id: "MO", name: "Missouri", countyCount: 115, latitude: 38.456085, longitude: -92.288368),
        USStateInfo(id: "MT", name: "Montana", countyCount: 56, latitude: 46.921925, longitude: -110.454353),
        USStateInfo(id: "NE", name: "Nebraska", countyCount: 93, latitude: 41.125370, longitude: -98.268082),
        USStateInfo(id: "NV", name: "Nevada", countyCount: 17, latitude: 38.313515, longitude: -117.055374),
        USStateInfo(id: "NH", name: "New Hampshire", countyCount: 10, latitude: 43.452492, longitude: -71.563896),
        USStateInfo(id: "NJ", name: "New Jersey", countyCount: 21, latitude: 40.298904, longitude: -74.521011),
        USStateInfo(id: "NM", name: "New Mexico", countyCount: 33, latitude: 34.840515, longitude: -106.248482),
        USStateInfo(id: "NY", name: "New York", countyCount: 62, latitude: 42.165726, longitude: -74.948051),
        USStateInfo(id: "NC", name: "North Carolina", countyCount: 100, latitude: 35.630066, longitude: -79.806419),
        USStateInfo(id: "ND", name: "North Dakota", countyCount: 53, latitude: 47.528912, longitude: -99.784012),
        USStateInfo(id: "OH", name: "Ohio", countyCount: 88, latitude: 40.388783, longitude: -82.764915),
        USStateInfo(id: "OK", name: "Oklahoma", countyCount: 77, latitude: 35.565342, longitude: -96.928917),
        USStateInfo(id: "OR", name: "Oregon", countyCount: 36, latitude: 44.572021, longitude: -122.070938),
        USStateInfo(id: "PA", name: "Pennsylvania", countyCount: 67, latitude: 40.590752, longitude: -77.209755),
        USStateInfo(id: "RI", name: "Rhode Island", countyCount: 5, latitude: 41.680893, longitude: -71.511780),
        USStateInfo(id: "SC", name: "South Carolina", countyCount: 46, latitude: 33.856892, longitude: -80.945007),
        USStateInfo(id: "SD", name: "South Dakota", countyCount: 66, latitude: 44.299782, longitude: -99.438828),
        USStateInfo(id: "TN", name: "Tennessee", countyCount: 95, latitude: 35.747845, longitude: -86.692345),
        USStateInfo(id: "TX", name: "Texas", countyCount: 254, latitude: 31.054487, longitude: -97.563461),
        USStateInfo(id: "UT", name: "Utah", countyCount: 29, latitude: 40.150032, longitude: -111.862434),
        USStateInfo(id: "VT", name: "Vermont", countyCount: 14, latitude: 44.045876, longitude: -72.710686),
        USStateInfo(id: "VA", name: "Virginia", countyCount: 133, latitude: 37.769337, longitude: -78.169968),
        USStateInfo(id: "WA", name: "Washington", countyCount: 39, latitude: 47.400902, longitude: -121.490494),
        USStateInfo(id: "WV", name: "West Virginia", countyCount: 55, latitude: 38.491226, longitude: -80.954456),
        USStateInfo(id: "WI", name: "Wisconsin", countyCount: 72, latitude: 44.268543, longitude: -89.616508),
        USStateInfo(id: "WY", name: "Wyoming", countyCount: 23, latitude: 42.755966, longitude: -107.302490),
    ]

    nonisolated private static let nameToAbbreviation: [String: String] = {
        Dictionary(uniqueKeysWithValues: allStates.map { ($0.name, $0.id) })
    }()

    nonisolated static func abbreviation(for fullName: String) -> String? {
        nameToAbbreviation[fullName]
    }

    nonisolated static func stateInfo(for abbreviation: String) -> USStateInfo? {
        allStates.first { $0.id == abbreviation }
    }
}
