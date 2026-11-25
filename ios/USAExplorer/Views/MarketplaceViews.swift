import SwiftUI
import MapKit

// MARK: - Marketplace Browse

/// Searchable, category-filtered catalog of public layers.
struct MarketplaceBrowseView: View {
    @State private var service = MarketplaceService.shared
    @State private var pass = PassService.shared
    @State private var searchText = ""
    @State private var category: OverlayCategory?
    @State private var detail: OverlayDefinitionDTO?
    @State private var paywallDefinition: OverlayDefinitionDTO?

    private let surface = Color(red: 0.07, green: 0.09, blue: 0.16)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    private var filtered: [OverlayDefinitionDTO] {
        service.catalog.filter { definition in
            guard category == nil || MarketplaceService.category(definition) == category else { return false }
            let query = searchText.trimmingCharacters(in: .whitespaces)
            if query.isEmpty { return true }
            return definition.name.localizedCaseInsensitiveContains(query)
                || definition.summary.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    categoryChips

                    if service.isLoadingCatalog && service.catalog.isEmpty {
                        ProgressView()
                            .tint(gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "storefront")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.3))
                            Text(service.lastCatalogError ?? "No layers yet. Be the first to publish one.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filtered) { definition in
                            catalogRow(definition)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Marketplace")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search layers")
        .refreshable { await service.refreshCatalog() }
        .task { await service.refreshCatalog() }
        .sheet(item: $detail) { definition in
            OverlayDetailView(definition: definition, paywall: showPaywall)
        }
        .sheet(item: $paywallDefinition) { definition in
            PaywallView(definition: definition)
        }
    }

    private func showPaywall(_ definition: OverlayDefinitionDTO) {
        paywallDefinition = definition
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, label: "All")
                ForEach(OverlayCategory.allCases) { category in
                    chip(category, label: category.displayName)
                }
            }
        }
    }

    private func chip(_ value: OverlayCategory?, label: String) -> some View {
        let isSelected = category == value
        return Button {
            withAnimation(.snappy) { category = value }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color(red: 10/255, green: 15/255, blue: 30/255) : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? gold : surface)
                .clipShape(Capsule())
        }
    }

    private func catalogRow(_ definition: OverlayDefinitionDTO) -> some View {
        Button { detail = definition } label: {
            HStack(spacing: 12) {
                Image(systemName: definition.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(gold)
                    .frame(width: 38, height: 38)
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(definition.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(definition.summary.isEmpty ? MarketplaceService.category(definition).displayName : definition.summary)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        stars(definition.ratingAvg, size: 9)
                        Text("\(definition.ratingCount)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.4))
                        Text("· \(definition.installs) installs")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Spacer()

                if service.isInstalled(definition) {
                    Text("Installed")
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(gold)
                } else if definition.isPaid {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(gold)
                }
            }
            .padding(12)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stars(_ rating: Double, size: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: Double(index) < rating.rounded(.up) ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(gold.opacity(Double(index) < rating.rounded(.up) ? 1 : 0.25))
            }
        }
    }
}

// MARK: - Layer Detail

struct OverlayDetailView: View {
    let definition: OverlayDefinitionDTO
    let paywall: (OverlayDefinitionDTO) -> Void

    @State private var service = MarketplaceService.shared
    @State private var pass = PassService.shared
    @State private var reviews: [OverlayReviewDTO] = []
    @State private var myRating = 5
    @State private var myReview = ""
    @State private var showReport = false
    @State private var reportSent = false
    @State private var isBusy = false

    private let surface = Color(red: 0.07, green: 0.09, blue: 0.16)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    private var needsUnlock: Bool {
        MarketplaceService.requiresPass(definition) && !pass.isPassActive
    }

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    installButton
                    statsRow
                    reviewsSection
                    reportSection
                }
                .padding(16)
            }
        }
        .task { reviews = await SupabaseService.shared.fetchOverlayReviews(overlayId: definition.id) }
        .confirmationDialog("Report this layer", isPresented: $showReport, titleVisibility: .visible) {
            Button("Inaccurate or spam") { report("inaccurate_or_spam") }
            Button("Privacy concern") { report("privacy_concern") }
            Button("Inappropriate content", role: .destructive) { report("inappropriate") }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: definition.systemImage)
                .font(.title2)
                .foregroundStyle(gold)
                .frame(width: 52, height: 52)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(MarketplaceService.category(definition).displayName) · \(definition.spec.features.count) points · v\(definition.version)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
    }

    private var installButton: some View {
        Button {
            if service.isInstalled(definition) {
                service.uninstall(definition)
            } else if needsUnlock {
                paywall(definition)
            } else {
                Task {
                    isBusy = true
                    await service.install(definition)
                    isBusy = false
                }
            }
        } label: {
            HStack {
                if isBusy {
                    ProgressView().tint(Color(red: 10/255, green: 15/255, blue: 30/255))
                } else {
                    Image(systemName: service.isInstalled(definition) ? "minus.circle.fill" : (definition.isPaid ? "lock.open.fill" : "plus.circle.fill"))
                    Text(service.isInstalled(definition)
                         ? "Uninstall"
                         : needsUnlock ? "Unlock with All-Access Pass" : "Install")
                        .font(.subheadline.weight(.bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(service.isInstalled(definition) ? surface : gold)
            .foregroundStyle(service.isInstalled(definition) ? .white : Color(red: 10/255, green: 15/255, blue: 30/255))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("\(definition.installs)", "INSTALLS")
            stat(String(format: "%.1f", definition.ratingAvg), "RATING")
            stat("\(definition.ratingCount)", "REVIEWS")
            stat(definition.pricing == "paid" ? "PASS" : "FREE", "PRICING")
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold).monospaced())
                .foregroundStyle(gold)
            Text(caption)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews")
                .font(.headline)
                .foregroundStyle(.white)

            if let userId = UserProfileService.shared.userId {
                reviewComposer(userId: userId)
            }

            ForEach(reviews) { review in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(Self.shortId(review.userId))
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        starsRow(review.rating)
                    }
                    if !review.body.isEmpty {
                        Text(review.body)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(12)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func reviewComposer(userId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Rating", selection: $myRating) {
                    ForEach(1...5, id: \.self) { Text("\($0) ★").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                Button("Post") {
                    Task {
                        let inserted = OverlayReviewInsert(
                            overlayId: definition.id,
                            userId: userId,
                            rating: myRating,
                            body: myReview.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        if await SupabaseService.shared.submitOverlayReview(inserted) {
                            myReview = ""
                            reviews = await SupabaseService.shared.fetchOverlayReviews(overlayId: definition.id)
                        }
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(gold)
            }

            TextField("Share what this layer helps you find…", text: $myReview, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .padding(12)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func starsRow(_ rating: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(gold.opacity(index < rating ? 1 : 0.25))
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showReport = true
            } label: {
                Label(reportSent ? "Reported — our moderators will review" : "Report layer",
                      systemImage: "flag")
                    .font(.caption)
                    .foregroundStyle(reportSent ? .white.opacity(0.4) : .white.opacity(0.6))
            }
            .disabled(reportSent)

            Text("Cameras and enforcement layers are reviewed before going live.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func report(_ reason: String) {
        guard let userId = UserProfileService.shared.userId else { return }
        Task {
            let insert = OverlayReportInsert(overlayId: definition.id, reporterUserId: userId, reason: reason)
            if await SupabaseService.shared.reportOverlay(insert) {
                reportSent = true
            }
        }
    }

    private static func shortId(_ id: String) -> String {
        let start = id.index(id.startIndex, offsetBy: min(6, id.count))
        return "explorer \(id[..<start])"
    }
}

// MARK: - All-Access Pass Paywall

/// Apple-compliant paywall for the single monthly All-Access subscription.
struct PaywallView: View {
    let definition: OverlayDefinitionDTO?

    @State private var pass = PassService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://www.apple.com/legal/privacy/")!

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Headline: price and period are the first thing seen.
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pass.priceLabel ?? "ALL-ACCESS PASS")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(gold)
                            Text("per month · cancels anytime")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.top, 24)

                        VStack(alignment: .leading, spacing: 14) {
                            benefit("lock.open.fill", "Every paid layer, unlocked",
                                    "One pass covers all paid marketplace layers — current and future.")
                            benefit("map.fill", "Publish paid layers",
                                    "Creators keep publishing; you install everything the moment it drops.")
                            benefit("wifi.slash", "Works offline",
                                    "A recently verified pass keeps working through short connectivity gaps.")
                        }

                        if let definition {
                            Text("Continues to \"\(definition.name)\" after purchase.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .padding(20)
                }

                VStack(spacing: 10) {
                    if let error = pass.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task {
                            if await pass.purchase() { dismiss() }
                        }
                    } label: {
                        HStack {
                            if pass.isPurchasing {
                                ProgressView().tint(Color(red: 10/255, green: 15/255, blue: 30/255))
                            } else {
                                Text(pass.isPassActive ? "Pass active" : "Subscribe")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(pass.isPassActive ? Color.white.opacity(0.1) : gold)
                        .foregroundStyle(pass.isPassActive ? .white : Color(red: 10/255, green: 15/255, blue: 30/255))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(pass.isPurchasing || !pass.isConfigured || pass.isPassActive)

                    if !pass.isConfigured {
                        Text("Purchases aren't set up yet in this build.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    HStack(spacing: 20) {
                        Button("Restore") {
                            Task {
                                if await pass.restore() { dismiss() }
                            }
                        }
                        Button("Terms of Use") { openURL(Self.termsURL) }
                        Button("Privacy Policy") { openURL(Self.privacyURL) }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.55))

                    Text("Payment is charged to your Apple ID account at confirmation of purchase. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .padding(.bottom, 8)
            }
        }
        .task { await pass.refresh() }
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(gold)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Creator Studio

/// Author and publish a layer: metadata, points, visibility, pricing.
struct CreatorStudioView: View {
    @State private var name = ""
    @State private var summary = ""
    @State private var category: OverlayCategory = .navigation
    @State private var systemImage = "mappin.and.ellipse"
    @State private var visibility = "public"
    @State private var isPaid = false
    @State private var points: [OverlaySpecFeature] = []
    @State private var pinDropSheet = false
    @State private var isPublishing = false
    @State private var publishError: String?

    @Environment(\.dismiss) private var dismiss

    private let surface = Color(red: 0.07, green: 0.09, blue: 0.16)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)
    private let iconChoices = ["mappin.and.ellipse", "star.fill", "camera.fill", "fork.knife", "binoculars.fill", "leaf.fill", "flag.fill", "paintpalette.fill"]

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metadataSection
                    categorySection
                    pointsSection
                    publishSection
                }
                .padding(16)
            }
        }
        .navigationTitle("Creator Studio")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pinDropSheet) {
            PinDropSheet(points: $points)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layer details")
                .font(.headline)
                .foregroundStyle(.white)

            TextField("Layer name", text: $name)
                .font(.subheadline)
                .padding(12)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            TextField("What does it show explorers?", text: $summary, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(12)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(iconChoices, id: \.self) { icon in
                        Button { systemImage = icon } label: {
                            Image(systemName: icon)
                                .font(.subheadline)
                                .foregroundStyle(systemImage == icon ? Color(red: 10/255, green: 15/255, blue: 30/255) : .white.opacity(0.6))
                                .frame(width: 38, height: 38)
                                .background(systemImage == icon ? gold : surface)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category & visibility")
                .font(.headline)
                .foregroundStyle(.white)

            Picker("Category", selection: $category) {
                ForEach(OverlayCategory.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if category.isSensitive {
                Label("Camera and enforcement layers publish as \"pending review\" and go live after moderation.", systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(gold)
            }

            Picker("Visibility", selection: $visibility) {
                Text("Private").tag("private")
                Text("Shared link").tag("shared")
                Text("Public").tag("public")
            }
            .pickerStyle(.segmented)

            Picker("Pricing", selection: $isPaid) {
                Text("Free").tag(false)
                Text("Pass unlock").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var pointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Points")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(points.count) ADDED")
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(gold)
            }

            ForEach($points) { $point in
                HStack {
                    Image(systemName: "mappin")
                        .font(.caption)
                        .foregroundStyle(gold)
                    TextField("Point title", text: $point.title)
                        .font(.subheadline)
                    TextField("Note", text: $point.note)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Button(role: .destructive) {
                        points.removeAll { $0.id == point.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(10)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                pinDropSheet = true
            } label: {
                Label("Add points on the map", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(gold.opacity(0.15))
                    .foregroundStyle(gold)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var publishSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let publishError {
                Text(publishError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
            }

            Button {
                publish()
            } label: {
                HStack {
                    if isPublishing {
                        ProgressView().tint(Color(red: 10/255, green: 15/255, blue: 30/255))
                    } else {
                        Text("Publish layer")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(gold)
                .foregroundStyle(Color(red: 10/255, green: 15/255, blue: 30/255))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isPublishing)

            Text("Publishing uses your anonymous explorer id — no account needed. You can delete your layer anytime from My Layers.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func publish() {
        guard let userId = UserProfileService.shared.userId else {
            publishError = "Explorer profile not ready yet. Try again in a moment."
            return
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            publishError = "Give your layer a name first."
            return
        }
        guard !points.isEmpty else {
            publishError = "Add at least one point on the map."
            return
        }

        let insert = OverlayDefinitionInsert(
            id: UUID().uuidString.lowercased(),
            creatorUserId: userId,
            name: name.trimmingCharacters(in: .whitespaces),
            version: 1,
            spec: OverlaySpec(
                featureKind: OverlayFeatureKind.custom.rawValue,
                category: category.rawValue,
                features: points
            ),
            visibility: visibility,
            pricing: isPaid ? "paid" : "free",
            category: category.rawValue,
            summary: summary.trimmingCharacters(in: .whitespaces),
            systemImage: systemImage,
            status: category.isSensitive ? "pending_review" : "active",
            coordinateSystem: "EPSG:4326"
        )

        isPublishing = true
        Task {
            let ok = await SupabaseService.shared.publishOverlay(insert)
            isPublishing = false
            if ok {
                await SocialService.post(kind: "layer", title: "published a new layer: \(insert.name)")
                dismiss()
            } else {
                publishError = "Couldn't publish right now. Check your connection and try again."
            }
        }
    }
}

/// Drop-pin sheet: a small map where taps add points with a title and note.
struct PinDropSheet: View {
    @Binding var points: [OverlaySpecFeature]
    @Environment(\.dismiss) private var dismiss

    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            VStack(spacing: 0) {
                PinDropMapView(points: points) { coordinate in
                    let point = OverlaySpecFeature(
                        id: UUID().uuidString,
                        lat: coordinate.latitude,
                        lng: coordinate.longitude,
                        title: "Point \(points.count + 1)",
                        note: ""
                    )
                    points.append(point)
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tap the map to drop a pin")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(gold)
                    }
                    Text("\(points.count) points · name and note each one in the list below the map button.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(16)
            }
        }
    }
}

/// MKMapView wrapper with a tap-to-coordinate gesture for pin dropping.
struct PinDropMapView: UIViewRepresentable {
    var points: [OverlaySpecFeature]
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.showsUserLocation = true
        map.isPitchEnabled = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)

        // Start over the continental US; the user pans to their area.
        if map.annotations.isEmpty {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                latitudinalMeters: 2_000_000,
                longitudinalMeters: 2_000_000
            )
            map.setRegion(region, animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        for annotation in map.annotations where annotation is MKPointAnnotation {
            map.removeAnnotation(annotation)
        }
        for feature in points {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: feature.lat, longitude: feature.lng)
            annotation.title = feature.title
            annotation.subtitle = feature.note
            map.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: PinDropMapView
        init(parent: PinDropMapView) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let location = gesture.location(in: map)
            parent.onTap(map.convert(location, toCoordinateFrom: map))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.markerTintColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)
            view.displayPriority = .required
            return view
        }
    }
}

// MARK: - My Layers (creator analytics)

struct MyLayersView: View {
    @State private var service = MarketplaceService.shared
    @State private var mine: [OverlayDefinitionDTO] = []
    @State private var dailyInstalls: [String: [DailyInstallDTO]] = [:]
    @State private var isLoading = true

    private let surface = Color(red: 0.07, green: 0.09, blue: 0.16)
    private let gold = Color(red: 245/255, green: 197/255, blue: 24/255)

    var body: some View {
        ZStack {
            Color(red: 10/255, green: 15/255, blue: 30/255).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    totals

                    if isLoading {
                        ProgressView().tint(gold).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if mine.isEmpty {
                        Text("You haven't published a layer yet. Open Creator Studio to make your first one.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.vertical, 30)
                    } else {
                        ForEach(mine) { definition in
                            VStack(spacing: 8) {
                                myLayerRow(definition)
                                if let daily = dailyInstalls[definition.id], !daily.isEmpty {
                                    installSparkline(daily)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("My Layers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        isLoading = mine.isEmpty
        if let userId = UserProfileService.shared.userId {
            mine = await SupabaseService.shared.fetchMyOverlays(creatorId: userId)
            // Phase 4 creator analytics: 30-day install sparklines.
            var installs: [String: [DailyInstallDTO]] = [:]
            for definition in mine {
                installs[definition.id] = await SupabaseService.shared.fetchOverlayDailyInstalls(overlayId: definition.id)
            }
            dailyInstalls = installs
        }
        isLoading = false
    }

    /// 30-day install sparkline — one gold bar per day with installs.
    private func installSparkline(_ daily: [DailyInstallDTO]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAST 30 DAYS")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.35))

            HStack(alignment: .bottom, spacing: 2) {
                let byDay = Dictionary(uniqueKeysWithValues: daily.map { ($0.day, $0.installs) })
                let maxInstalls = max(1, daily.map(\.installs).max() ?? 1)
                let days = last30Days()
                ForEach(days, id: \.self) { day in
                    let installs = byDay[day] ?? 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(installs > 0 ? gold : Color.white.opacity(0.08))
                        .frame(height: installs > 0 ? CGFloat(6 + 22 * installs / maxInstalls) : 6)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 30)
        }
        .padding(10)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func last30Days() -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<30).reversed().compactMap { offset in
            formatter.string(from: Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
        }
    }

    private var totals: some View {
        HStack(spacing: 10) {
            totalStat("\(mine.count)", "LAYERS")
            totalStat("\(mine.reduce(0) { $0 + $1.installs })", "INSTALLS")
            totalStat(String(format: "%.1f", mine.first?.ratingAvg ?? 0), "TOP RATING")
        }
    }

    private func totalStat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospaced())
                .foregroundStyle(gold)
            Text(caption)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func myLayerRow(_ definition: OverlayDefinitionDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: definition.systemImage)
                .font(.subheadline)
                .foregroundStyle(gold)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(definition.statusLabel) · \(definition.installs) installs · ★ \(String(format: "%.1f", definition.ratingAvg)) (\(definition.ratingCount))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    Task {
                        if let userId = UserProfileService.shared.userId {
                            _ = await SupabaseService.shared.deleteOverlay(overlayId: definition.id, creatorId: userId)
                            if service.isInstalled(definition) { service.uninstall(definition) }
                            await reload()
                        }
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(12)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
