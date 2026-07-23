import SwiftUI
#if canImport(UIKit)
import UIKit
import SafariServices
#endif

struct BirdInfo: Codable {
    let species: String
    let description: String
    let imageURL: String?
    let wikiURL: String
    let ebirdURL: String
    let allaboutbirdsURL: String
    let scientificName: String
    let family: String
    let order: String

    enum CodingKeys: String, CodingKey {
        case species, description, family, order
        case imageURL = "image_url"
        case wikiURL = "wiki_url"
        case ebirdURL = "ebird_url"
        case allaboutbirdsURL = "allaboutbirds_url"
        case scientificName = "scientific_name"
    }
}

struct BirdInfoView: View {
    let species: String
    @State private var info: BirdInfo?
    @State private var isLoading = true
    @State private var safariURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading bird info…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let info {
                    infoContent(info)
                } else {
                    unavailableView
                }
            }
            .navigationTitle(species)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $safariURL) { url in
                SafariView(url: url)
            }
        }
        .task { await loadInfo() }
    }

    @ViewBuilder
    private func infoContent(_ info: BirdInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image
                if let imgStr = info.imageURL, let imgURL = URL(string: imgStr) {
                    AsyncImage(url: imgURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 220).clipped()
                        default:
                            Rectangle().fill(Color(.secondarySystemBackground)).frame(height: 220)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    // Species header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.species)
                            .font(.title2.bold())
                        if !info.scientificName.isEmpty {
                            Text(info.scientificName)
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        if !info.family.isEmpty || !info.order.isEmpty {
                            HStack(spacing: 8) {
                                if !info.order.isEmpty { chip(info.order, color: .teal) }
                                if !info.family.isEmpty { chip(info.family, color: .indigo) }
                            }
                        }
                    }

                    // Description
                    if !info.description.isEmpty {
                        Text(info.description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // External links
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Learn More")
                            .font(.headline)

                        linkRow(title: "Wikipedia", icon: "globe", urlString: info.wikiURL)
                        linkRow(title: "eBird", icon: "map.fill", urlString: info.ebirdURL)
                        linkRow(title: "All About Birds", icon: "bird.fill", urlString: info.allaboutbirdsURL)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bird")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No info available for \"\(species)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func linkRow(title: String, icon: String, urlString: String) -> some View {
        if !urlString.isEmpty, let url = URL(string: urlString) {
            Button {
                safariURL = url
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 22)
                        .foregroundStyle(Color.teal)
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func loadInfo() async {
        isLoading = true
        defer { isLoading = false }
        info = try? await APIClient.shared.birdInfo(species: species)
    }
}

#if canImport(UIKit)
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
