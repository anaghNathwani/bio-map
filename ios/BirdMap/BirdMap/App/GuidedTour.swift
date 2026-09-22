import SwiftUI

enum AppTab: Int, Hashable {
    case map, report, leaders, profile
}

struct TourStep: Identifiable {
    enum Placement {
        case center                 // floating in the middle
        case aboveTab(AppTab)       // just above the tab bar, pointing down at a tab
        case belowSearch            // under the map's search bar, pointing up at it
    }

    let id: Int
    let tab: AppTab
    let icon: String
    let title: String
    let message: String
    let placement: Placement
}

enum GuidedTour {
    static let steps: [TourStep] = [
        TourStep(id: 0, tab: .map, icon: "bird.fill",
                 title: "Welcome to BirdMap",
                 message: "A quick tour of how to find, report and identify birds together with the community. It takes about a minute.",
                 placement: .center),
        TourStep(id: 1, tab: .map, icon: "map.fill",
                 title: "Explore the map",
                 message: "Each pin is a place where birds were reported. A number on a pin means several sightings there \u{2014} tap it to pick one. Tap a single pin to open its sighting.",
                 placement: .aboveTab(.map)),
        TourStep(id: 2, tab: .map, icon: "magnifyingglass",
                 title: "Search for anything",
                 message: "Use the search bar to look up a species, a note, a username or a place, then tap a result to jump straight to it. The bookmark button at the top left lists sightings you\u{2019}ve saved.",
                 placement: .belowSearch),
        TourStep(id: 3, tab: .report, icon: "camera.fill",
                 title: "Report a sighting",
                 message: "Choose Photo to take or pick a picture, or Audio to record up to 30 seconds of a bird call. The app suggests a species right on your phone.",
                 placement: .aboveTab(.report)),
        TourStep(id: 4, tab: .map, icon: "checklist",
                 title: "Help identify birds",
                 message: "Open any sighting and tap Annotate to add your own ID. You can also confirm the AI\u{2019}s guess or mark it wrong.",
                 placement: .center),
        TourStep(id: 5, tab: .leaders, icon: "trophy.fill",
                 title: "Climb the leaderboard",
                 message: "Every annotation you add counts toward your total on the Leaders board.",
                 placement: .aboveTab(.leaders)),
        TourStep(id: 6, tab: .profile, icon: "person.fill",
                 title: "Make it yours",
                 message: "Change your username, switch appearance and manage notifications here. You can replay this tour anytime with \u{201C}Take the tour\u{201D}.",
                 placement: .aboveTab(.profile)),
    ]
}

/// Dimmed coach-mark overlay that walks through `GuidedTour.steps`, switching
/// tabs behind it as it goes.
struct GuidedTourOverlay: View {
    @Binding var selectedTab: AppTab
    let onFinish: () -> Void

    @State private var index = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let steps = GuidedTour.steps
    private let tabCount: CGFloat = 4
    private let tabBarHeight: CGFloat = 49
    /// Nav bar + large title + search field, measured from the top safe area.
    private let searchBarBottom: CGFloat = 150

    private var step: TourStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture {}        // swallow taps so the app underneath stays inert
                content(in: geo)
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .onAppear { selectedTab = step.tab }
    }

    @ViewBuilder
    private func content(in geo: GeometryProxy) -> some View {
        switch step.placement {
        case .center:
            card
        case .aboveTab(let tab):
            VStack(spacing: 0) {
                Spacer()
                card
                if sizeClass == .compact {
                    pointer(up: false, at: (CGFloat(tab.rawValue) + 0.5) / tabCount, in: geo.size.width)
                }
            }
            .padding(.bottom, geo.safeAreaInsets.bottom + tabBarHeight)
        case .belowSearch:
            VStack(spacing: 0) {
                pointer(up: true, at: 0.5, in: geo.size.width)
                card
                Spacer()
            }
            .padding(.top, geo.safeAreaInsets.top + searchBarBottom)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.teal.opacity(0.15)).frame(width: 52, height: 52)
                Image(systemName: step.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.teal)
            }
            VStack(spacing: 6) {
                Text(step.title).font(.headline)
                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                ForEach(steps) { s in
                    Circle()
                        .fill(s.id == index ? Color.teal : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            HStack {
                if index > 0 {
                    Button("Back") { go(to: index - 1) }
                } else {
                    Button("Skip") { onFinish() }
                }
                Spacer()
                Text("\(index + 1) of \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isLast ? "Done" : "Next") {
                    if isLast { onFinish() } else { go(to: index + 1) }
                }
                .fontWeight(.semibold)
            }
            .font(.subheadline)
            .tint(.teal)

            if !isLast && index > 0 {
                Button("Skip tour") { onFinish() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: 400)
        .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 20)
        .id(step.id)
        .transition(.opacity)
    }

    private func pointer(up: Bool, at fraction: CGFloat, in width: CGFloat) -> some View {
        Triangle()
            .fill(Color(UIColor.systemBackground))
            .frame(width: 22, height: 11)
            .rotationEffect(.degrees(up ? 0 : 180))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, width * fraction - 11)
            .accessibilityHidden(true)
    }

    private func go(to newIndex: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            index = newIndex
            selectedTab = steps[newIndex].tab
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
