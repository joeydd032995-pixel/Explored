import SwiftUI
import CoreLocation

struct CheckInSheet: View {
    let coordinate: CLLocationCoordinate2D
    let address: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(gold)
                Text("Mark as Visited?")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(address.isEmpty ? "Unknown Location" : address)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(cardBg)
            .clipShape(.rect(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Confirm")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(darkNavy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(gold)
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .background(darkNavy)
    }
}
