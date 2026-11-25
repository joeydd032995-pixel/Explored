import SwiftUI
import MapKit

struct MiniUSMapView: View {
    let visitedStateIds: Set<String>

    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 50)
        )), interactionModes: []) {
            ForEach(USStateData.allStates) { state in
                let isVisited = visitedStateIds.contains(state.id)
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: state.latitude, longitude: state.longitude)) {
                    Circle()
                        .fill(isVisited ? gold : Color.white.opacity(0.12))
                        .frame(width: isVisited ? 10 : 6, height: isVisited ? 10 : 6)
                        .shadow(color: isVisited ? gold.opacity(0.6) : .clear, radius: 4)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .frame(height: 200)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
