import SwiftUI
import MapKit

struct ShareCardView: View {
    let nationalPercent: String
    let statesVisited: Int
    let countiesVisited: Int
    let visitedStateIds: Set<String>

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(gold)
                    Text("USA Explorer")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(gold)
                }
                .padding(.top, 24)

                Text("My Exploration Journey")
                    .font(.caption)
                    .foregroundStyle(secondary)
            }

            MiniUSMapView(visitedStateIds: visitedStateIds)
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 16)

            HStack(spacing: 20) {
                statItem(value: nationalPercent, label: "explored")
                statItem(value: "\(statesVisited)", label: "states")
                statItem(value: "\(countiesVisited)", label: "counties")
            }
            .padding(.vertical, 20)

            Text("Track your journey \u{00B7} USA Explorer App")
                .font(.caption2)
                .foregroundStyle(secondary)
                .padding(.bottom, 20)
        }
        .frame(width: 360)
        .background(darkNavy)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(gold.opacity(0.2), lineWidth: 1)
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(secondary)
        }
    }
}

struct ShareService {
    @MainActor
    static func shareCard(view: some View) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0

        guard let image = renderer.uiImage else { return }

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(activityVC, animated: true)
    }
}
