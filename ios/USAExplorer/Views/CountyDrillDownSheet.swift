import SwiftUI

struct CountyDrillDownSheet: View {
    let county: VisitedCountyRecord

    @State private var cities: [VisitedCityRecord] = []

    private let darkNavy = Color(red: 10/255, green: 15/255, blue: 30/255)
    private let cardBg = Color(red: 17/255, green: 24/255, blue: 39/255)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(county.state, systemImage: "mappin.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(gold)

                        Text(formatDate(county.visitedDate))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBg)
                    .clipShape(.rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(gold)
                            Text("Cities & Towns Visited")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(cities.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(gold)
                        }

                        if cities.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.white.opacity(0.3))
                                Text("No cities recorded in this county yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.vertical, 8)
                        } else {
                            ForEach(cities) { city in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.body)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(city.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.white)

                                        Text(formatDate(city.visitedDate))
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.4))
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(cardBg)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .padding()
            }
            .background(darkNavy)
            .navigationTitle(county.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(darkNavy, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            cities = DatabaseService.shared.fetchCitiesForCounty(county: county.name, state: county.state)
        }
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
