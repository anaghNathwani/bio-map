import WidgetKit
import SwiftUI
import AppIntents

// Lock-screen controls (the two buttons at the bottom corners of the Lock Screen, also in Control Center).
// iOS 18 and later; earlier systems simply don't offer them.

@available(iOS 18.0, *)
struct OpenPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Photograph a bird"
    static let description = IntentDescription("Opens BioMap's camera.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.photo))
    }
}

@available(iOS 18.0, *)
struct OpenSoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a bird call"
    static let description = IntentDescription("Opens BioMap's sound recorder.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetLink.sound))
    }
}

@available(iOS 18.0, *)
struct ReportPhotoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.biomap.control.photo") {
            ControlWidgetButton(action: OpenPhotoIntent()) {
                Label("Photograph a bird", systemImage: "camera.fill")
            }
        }
        .displayName("Photograph a bird")
        .description("Open BioMap's camera.")
    }
}

@available(iOS 18.0, *)
struct ReportSoundControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.biomap.control.sound") {
            ControlWidgetButton(action: OpenSoundIntent()) {
                Label("Record a bird call", systemImage: "waveform")
            }
        }
        .displayName("Record a bird call")
        .description("Open BioMap's sound recorder.")
    }
}
