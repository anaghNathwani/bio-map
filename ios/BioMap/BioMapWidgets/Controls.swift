import WidgetKit
import SwiftUI
import AppIntents

// The two Lock Screen corner controls (also in Control Center), iOS 18 and later. Their intents
// (OpenPhotoIntent / OpenSoundIntent) live in ControlIntents.swift, shared with the app.

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
