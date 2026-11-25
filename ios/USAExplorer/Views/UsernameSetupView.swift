import SwiftUI
import UIKit

struct UsernameSetupView: View {
    @State private var username: String = ""
    @State private var isSubmitting: Bool = false
    let onComplete: () -> Void

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        ZStack {
            darkNavy.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(gold)
                        .shadow(color: gold.opacity(0.4), radius: 20)

                    Text("USA Explorer")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(gold)

                    Text("Track your journey across America")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose your Explorer name")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(1)

                    TextField("", text: $username, prompt: Text("Enter username").foregroundStyle(.white.opacity(0.3)))
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(gold.opacity(username.isEmpty ? 0.2 : 0.6), lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 32)

                Button {
                    guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    isSubmitting = true
                    // Dismiss the keyboard BEFORE the view is replaced: removing a
                    // text field while it is first responder can deadlock UIKit's
                    // keyboard task queue (main-thread hang / frozen UI).
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    UserProfileService.shared.setupUser(username: username.trimmingCharacters(in: .whitespaces))
                    onComplete()
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(darkNavy)
                        }
                        Text("Start Exploring")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(darkNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        username.trimmingCharacters(in: .whitespaces).isEmpty
                            ? gold.opacity(0.3) : gold
                    )
                    .clipShape(.rect(cornerRadius: 14))
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
        }
    }
}
