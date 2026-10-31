import Foundation
import AppIntents

/// Deep links the widgets and controls open (handled by DeepLink in the app).
enum WidgetLink {
    static let photo = URL(string: "com.biomap.app://photo")!
    static let sound = URL(string: "com.biomap.app://sound")!
    static let map = URL(string: "com.biomap.app://map")!
}

/// Hand-off for the lock-screen controls. This file is compiled into BOTH the app and the widget extension:
/// iOS runs an app-opening control's intent inside the app process, so the intent type has to exist in the
/// app too (when it only lived in the extension, tapping the control did nothing).
enum ControlRoute {
    static let requested = Notification.Name("com.biomap.controlRouteRequested")
    private static var pending: String?

    /// Called from the intent. When it runs inside the app, the app picks this up; when it runs in the
    /// extension instead, the OpenURLIntent result below opens the app via its URL.
    static func request(_ route: String) {
        pending = route
        DispatchQueue.main.async { NotificationCenter.default.post(name: requested, object: route) }
    }

    /// The app calls this on launch / when it becomes active.
    static func takePending() -> String? {
        defer { pending = nil }
        return pending
    }
}

// Lock-screen controls (the two buttons at the bottom corners of the Lock Screen, also in Control Center).
// iOS 18 and later; earlier systems simply don't offer them.

@available(iOS 18.0, *)
struct OpenPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Photograph a bird"
    static let description = IntentDescription("Opens BioMap's camera.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    func perform() async throws -> some IntentResult & OpensIntent {
        ControlRoute.request("photo")
        return .result(opensIntent: OpenURLIntent(WidgetLink.photo))
    }
}

@available(iOS 18.0, *)
struct OpenSoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a bird call"
    static let description = IntentDescription("Opens BioMap's sound recorder.")
    static var openAppWhenRun: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    func perform() async throws -> some IntentResult & OpensIntent {
        ControlRoute.request("sound")
        return .result(opensIntent: OpenURLIntent(WidgetLink.sound))
    }
}
