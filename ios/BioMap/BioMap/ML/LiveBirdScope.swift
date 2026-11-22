import AVFoundation
import Vision
import CoreImage
import UIKit

/// One bird the live scope is following.
struct LiveBird: Identifiable, Equatable {
    let id: Int
    /// Normalised (0...1) in the camera frame, top-left origin.
    var box: CGRect
    /// Best guess so far; nil until the species model has had a look.
    var species: String?
    var confidence: Float = 0
}

