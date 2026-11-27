import SwiftUI

struct StatCardView: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let progress: Double?

    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    init(icon: String, title: String, value: String, subtitle: String? = nil, progress: Double? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.progress = progress
    }

    var body: some View {
        HStack(spacing: 0) {
            gold
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(icon)
                        .font(.title3)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()
                }

                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                if let progress {
                    GoldProgressBar(progress: progress)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct GoldProgressBar: View {
    let progress: Double

    var body: some View {
        ThemedProgressBar(percent: progress * 100)
    }
}
