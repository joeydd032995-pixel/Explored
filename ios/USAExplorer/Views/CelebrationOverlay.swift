import SwiftUI

struct CelebrationOverlay: View {
    let stateName: String
    let isVisible: Bool

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        if isVisible {
            VStack(spacing: 16) {
                Text("\u{1F389}")
                    .font(.system(size: 52))

                Text("New State Unlocked!")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(gold.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(2)

                Text(stateName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(darkNavy)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(gold.opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: gold.opacity(0.3), radius: 30, y: 8)
            )
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}
