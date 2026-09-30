import SwiftUI
#if canImport(UIKit)
import UIKit
import SafariServices
#endif


struct BirdInfoView: View {
    let species: String
    @State private var info: BirdInfo?
    @State private var isLoading = true
    @State private var safariURL: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = ThemeColors(scheme: scheme)
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading bird info…")
                        .tint(c.clay)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(c.paper)
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
        let c = ThemeColors(scheme: scheme)
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
                            Rectangle().fill(c.paperDim).frame(height: 220)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    // Species header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.species)
                            .font(Theme.display(24, medium: true))
                            .foregroundStyle(c.ink)
                        if !info.scientificName.isEmpty {
                            Text(info.scientificName)
                                .font(Theme.displayItalic(15))
                                .foregroundStyle(c.inkSoft)
                        }
                        if !info.family.isEmpty || !info.order.isEmpty {
                            HStack(spacing: 8) {
                                if !info.order.isEmpty { chip(info.order) }
                                if !info.family.isEmpty { chip(info.family) }
                            }
                        }
                    }

                    // Description
                    if !info.description.isEmpty {
                        Text(info.description)
                            .font(Theme.sans(15))
                            .foregroundStyle(c.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // External links
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Learn more")

                        linkRow(title: "Wikipedia", icon: "globe", urlString: info.wikiURL)
                        linkRow(title: "eBird", icon: "map.fill", urlString: info.ebirdURL)
                        linkRow(title: "All About Birds", icon: "bird.fill", urlString: info.allaboutbirdsURL)
                    }
                    .padding(16)
                    .background(c.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
                }
                .padding(16)
            }
        }
        .background(c.paper)
    }

    private var unavailableView: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(spacing: 16) {
            BirdMark()
                .stroke(c.inkSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 56, height: 56)
            Text("No info available for \"\(species)\"")
                .font(Theme.sans(14))
                .foregroundStyle(c.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.paper)
    }

    private func chip(_ text: String) -> some View {
        let c = ThemeColors(scheme: scheme)
        return Text(text)
            .font(Theme.sansMedium(12))
            .foregroundStyle(c.clay)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(c.clay.opacity(0.45), lineWidth: 1.2))
    }

    @ViewBuilder
    private func linkRow(title: String, icon: String, urlString: String) -> some View {
        let c = ThemeColors(scheme: scheme)
        if !urlString.isEmpty, let url = URL(string: urlString) {
            Button {
                safariURL = url
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .frame(width: 22)
                        .foregroundStyle(c.clay)
                    Text(title)
                        .font(Theme.sans(15))
                        .foregroundStyle(c.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(c.inkSoft)
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

#Preview {
    BirdInfoView(species: "American Robin")
}
