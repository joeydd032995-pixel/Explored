import SwiftUI

struct StateDrillDownSheet: View {
    let stateSummary: StateSummary

    @State private var counties: [VisitedCountyRecord] = []
    @State private var cities: [VisitedCityRecord] = []
    @State private var selectedCounty: VisitedCountyRecord?

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    progressSection
                    countyListSection
                }
                .padding()
            }
            .background(darkNavy)
            .navigationTitle(stateSummary.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { loadData() }
        .sheet(item: $selectedCounty) { county in
            CountyDrillDownSheet(county: county)
                .presentationDetents([.fraction(0.8)])
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: "%.1f%%", stateSummary.explorationPercent))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(gold)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("explored")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(stateSummary.totalCounties) counties total")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            GoldProgressBar(progress: stateSummary.explorationPercent / 100.0)
        }
        .padding()
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var progressSection: some View {
        HStack(spacing: 12) {
            progressCard(
                icon: "building.columns.fill",
                label: "Counties",
                count: counties.count,
                total: stateSummary.totalCounties
            )

            progressCard(
                icon: "building.2.fill",
                label: "Cities",
                count: cities.count,
                total: nil
            )
        }
    }

    private func progressCard(icon: String, label: String, count: Int, total: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(gold)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            if let total {
                Text("\(count) / \(total)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                GoldProgressBar(progress: total > 0 ? Double(count) / Double(total) : 0)
            } else {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var countyListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Counties")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(counties.count) visited")
                    .font(.caption)
                    .foregroundStyle(gold)
            }

            if counties.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No counties visited yet")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("\(stateSummary.totalCounties) counties to explore")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(counties) { county in
                        Button {
                            selectedCounty = county
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(county.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)

                                    Text(formatDate(county.visitedDate))
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.4))
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .background(cardBg)
                .clipShape(.rect(cornerRadius: 12))

                if counties.count < stateSummary.totalCounties {
                    HStack(spacing: 6) {
                        Image(systemName: "square")
                            .foregroundStyle(.white.opacity(0.2))
                        Text("\(stateSummary.totalCounties - counties.count) more counties to discover")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func loadData() {
        counties = DatabaseService.shared.fetchCountiesForState(state: stateSummary.name)
        cities = DatabaseService.shared.fetchCitiesForState(state: stateSummary.name)
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
