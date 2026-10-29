import WidgetKit
import SwiftUI

@main
struct BioMapWidgetBundle: WidgetBundle {
    var body: some Widget {
        SightingsWidget()                 // home screen + lock screen widgets
        if #available(iOS 18.0, *) {
            ReportPhotoControl()          // the two lock-screen corner buttons (and Control Center)
            ReportSoundControl()
        }
    }
}
