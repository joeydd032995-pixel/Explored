import SwiftUI

// MARK: - Privacy Settings (phase 4)
//
// Pause-all-tracking gate, approximate-location note, date-range deletion,
// JSON export, and full erasure. Dark-navy visual language.

struct PrivacySettingsView: View {
    @State private var privacy = PrivacyService.shared
    @State private var showEraseConfirmation = false
    @State private var exportURL: URL?

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let secondary = Color(red: 136/255, green: 153/255, blue: 170/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    trackingSection
                    deletionSection
                    exportSection
                    erasureSection
                    if let message = privacy.lastMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    privacyNote
                }
                .padding(.bottom, 24)
            }
            .background(darkNavy)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var trackingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracking")
                .font(.headline)
                .foregroundStyle(.white)

            Toggle(isOn: $privacy.isTrackingPaused) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause all tracking")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text("Stops every location write: no breadcrumbs, no hex discoveries, no stats.")
                        .font(.caption2)
                        .foregroundStyle(secondary)
                }
            }
            .tint(.red)

            Text("Your breadcrumbs stay on this device. Only aggregate counts — states, counties, unique cells — ever leave it.")
                .font(.caption2)
                .foregroundStyle(secondary)
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var deletionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete by date range")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Removes breadcrumbs, visits and per-state stats in the range. Unique-cell discoveries are kept — they power your percentages.")
                .font(.caption2)
                .foregroundStyle(secondary)

            ForEach(PrivacyService.DeleteRange.allCases.filter { $0 != .all }) { range in
                Button {
                    privacy.deleteData(in: range)
                } label: {
                    HStack {
                        Text(range.label)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .clipShape(.rect(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export my data")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Everything the app knows about you — breadcrumbs, visits, discoveries — as a JSON file you keep.")
                .font(.caption2)
                .foregroundStyle(secondary)

            Button {
                exportURL = privacy.exportJSON()
            } label: {
                Label("Export as JSON", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(darkNavy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(gold)
                    .clipShape(.rect(cornerRadius: 12))
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share export file", systemImage: "square.and.arrow.up.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(gold.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var erasureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Erase everything")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Wipes all exploration data on this device AND on the server: cell claims, analytics rows, feed posts.")
                .font(.caption2)
                .foregroundStyle(secondary)

            Button {
                showEraseConfirmation = true
            } label: {
                Text("Erase all my data")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.25))
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.horizontal)
        .confirmationDialog(
            "Erase all exploration data?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) {
                Task { await privacy.eraseEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your percentages, discoveries and server-side claims are permanently deleted.")
        }
    }

    private var privacyNote: some View {
        Text("Identity is a random explorer id stored on this device — no account, no email. Location is shared with other players only during a live Territory Game and is removed when it ends.")
            .font(.caption2)
            .foregroundStyle(secondary)
            .padding(.horizontal)
    }

    private var cardBg: Color { Color(red: 17/255, green: 24/255, blue: 39/255) }
}

