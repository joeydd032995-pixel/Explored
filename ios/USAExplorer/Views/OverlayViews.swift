import SwiftUI
import MapKit
import CoreLocation

// MARK: - Filter Sheet

struct OverlayFilterSheet: View {
    @Bindable var registry: OverlayRegistry
    @Environment(\.dismiss) private var dismiss

    private let surface = Color(red: 0.07, green: 0.09, blue: 0.16)

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                Text("Map Layers")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    ForEach(registry.providers, id: \.id) { provider in
                        providerRow(provider)
                    }
                }

                Spacer()

                Text("Overlays are independent, versioned data layers. Community features carry provenance and confidence; ephemeral reports decay automatically.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
        }
    }

    private func providerRow(_ provider: any OverlayProvider) -> some View {
        let enabled = registry.isEnabled(provider.id)

        return HStack(spacing: 14) {
            Image(systemName: provider.systemImage)
                .font(.headline)
                .foregroundStyle(enabled ? Color(red: 245/255, green: 197/255, blue: 24/255) : .white.opacity(0.35))
                .frame(width: 38, height: 38)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if provider.isSensitive {
                        Text("MODERATED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text("\(provider.featureCount) features · v\(provider.version)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { registry.isEnabled(provider.id) },
                set: { registry.setEnabled($0, for: provider.id) }
            ))
            .labelsHidden()
            .tint(Color(red: 245/255, green: 197/255, blue: 24/255))
        }
        .padding(14)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Hazard Report Sheet

struct ReportHazardSheet: View {
    let coordinate: CLLocationCoordinate2D
    let registry: OverlayRegistry
    var onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: OverlayFeatureKind = .police
    @State private var note: String = ""
    @State private var isSubmitting = false

    private let hazardKinds: [OverlayFeatureKind] = [.police, .speedTrap, .accident, .roadHazard, .construction]

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Report at Your Location")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.45))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(hazardKinds, id: \.rawValue) { kind in
                        kindButton(kind)
                    }
                }

                TextField("Note (optional)", text: $note)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)

                Button {
                    submit()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.black)
                        } else {
                            Text("Submit Report").fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 245/255, green: 197/255, blue: 24/255))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSubmitting)

                Text("Reports expire automatically. False reporting lowers your contribution trust score.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()
            }
            .padding(20)
        }
    }

    private func kindButton(_ kind: OverlayFeatureKind) -> some View {
        let selected = selectedKind == kind

        return Button {
            selectedKind = kind
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                Text(kind.displayName)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? .black : .white.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? Color(red: 245/255, green: 197/255, blue: 24/255) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            if let provider = registry.provider("hazards") as? HazardOverlayProvider {
                _ = await provider.submit(kind: selectedKind, coordinate: coordinate, note: note)
            }
            isSubmitting = false
            onSubmitted()
            dismiss()
        }
    }
}

// MARK: - Camera Report Sheet

struct ReportCameraSheet: View {
    let coordinate: CLLocationCoordinate2D
    let registry: OverlayRegistry
    var onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: OverlayFeatureKind = .alprFixed
    @State private var note: String = ""
    @State private var isSubmitting = false

    private let cameraKinds: [OverlayFeatureKind] = [.alprFixed, .alprMobile, .tollGantry, .redLight]

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Add Camera Point")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text(String(format: "%.5f, %.5f · WGS 84", coordinate.latitude, coordinate.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.45))

                VStack(spacing: 8) {
                    ForEach(cameraKinds, id: \.rawValue) { kind in
                        let selected = selectedKind == kind
                        Button {
                            selectedKind = kind
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: kind.systemImage)
                                    .frame(width: 22)
                                Text(kind.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(red: 245/255, green: 197/255, blue: 24/255))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(selected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(selected ? Color(red: 245/255, green: 197/255, blue: 24/255).opacity(0.6) : .clear, lineWidth: 1)
                            )
                        }
                    }
                }

                TextField("Describe placement (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)

                Button {
                    submit()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.black)
                        } else {
                            Text("Submit for Review").fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 245/255, green: 197/255, blue: 24/255))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSubmitting)

                Text("Camera contributions are sensitive and pass elevated moderation before wide publication. New points start at 40% confidence.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()
            }
            .padding(20)
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            if let provider = registry.provider("cameras") as? CameraOverlayProvider {
                _ = await provider.submit(kind: selectedKind, coordinate: coordinate, note: note)
            }
            isSubmitting = false
            onSubmitted()
            dismiss()
        }
    }
}

// MARK: - Feature Detail Sheet

struct OverlayFeatureDetailSheet: View {
    let feature: OverlayFeature
    let registry: OverlayRegistry
    var onUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: feature.kind.systemImage)
                        .font(.title3)
                        .foregroundStyle(Color(red: 245/255, green: 197/255, blue: 24/255))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(feature.kind.displayName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()
                }

                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                VStack(spacing: 8) {
                    detailRow(label: "Confidence", value: String(format: "%.0f%%", feature.confidence * 100))
                    detailRow(label: "Verifications", value: "\(feature.confirmations)")
                    detailRow(label: "Last verified", value: Self.timeLabel(feature.lastVerified))
                    detailRow(label: "Provenance", value: feature.source)

                    if let expiresAt = feature.expiresAt {
                        detailRow(label: "Expires", value: Self.timeLabel(expiresAt))
                    }

                    detailRow(label: "Coordinates (WGS 84)", value: String(format: "%.5f, %.5f", feature.coordinate.latitude, feature.coordinate.longitude))
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    confirmFeature()
                } label: {
                    HStack {
                        Image(systemName: confirmed ? "checkmark.circle.fill" : "hand.thumbsup")
                        Text(confirmed ? "Verified" : feature.kind.isEphemeral ? "Still there" : "Still accurate")
                    }
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(confirmed ? Color.white.opacity(0.12) : Color(red: 245/255, green: 197/255, blue: 24/255))
                    .foregroundStyle(confirmed ? .white : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(confirmed)

                Spacer()
            }
            .padding(20)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(.white)
        }
    }

    private func confirmFeature() {
        Task {
            let provider = registry.provider(feature.providerId)
            let updated = await provider?.confirm(feature)
            if updated != nil {
                HapticService.shared.reportConfirmed()
                confirmed = true
                onUpdated()
            }
        }
    }

    private static func timeLabel(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
