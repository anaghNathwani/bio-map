import SwiftUI
import AVFoundation

/// The same camera controls the main camera has (see LiveCameraVC), for the incognito live view: lens buttons and pinch
/// zoom measured in the native "1×" units, tap to focus with the yellow square, and drag up or down after a tap to change
/// exposure. Zoom is applied on the device, so the frames the bird detector sees are zoomed exactly like the preview.
@MainActor
final class ScopeCameraControls: ObservableObject {
    @Published private(set) var presets: [CGFloat] = []
    /// Current zoom in display units ("1×" is the main lens).
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var pinching = false

    weak var previewLayer: AVCaptureVideoPreviewLayer?
    let focusProxy = FocusSquareProxy()

    private var device: AVCaptureDevice?
    private var baseZoom: CGFloat = 1
    private var maxRawZoom: CGFloat = 1
    private var pinchStartRaw: CGFloat = 1
    private var zoomObservation: NSKeyValueObservation?
    private var subjectObserver: NSObjectProtocol?
    private var exposureBias: Float = 0
    private var dragStartBias: Float?

    /// The multi-lens virtual camera when the phone has one, so zoom hops between real lenses like the native app.
    nonisolated static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back).devices.first
    }

    func attach(_ device: AVCaptureDevice) {
        guard self.device == nil else { return }
        self.device = device
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        baseZoom = CameraZoom.base(hasUltraWide: hasUltraWide, switchOver: switchOver)
        maxRawZoom = min(device.maxAvailableVideoZoomFactor, baseZoom * CameraZoom.maxDisplayZoom)

        // Start on the main lens, not the ultra-wide.
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, baseZoom)
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }
        presets = CameraZoom.presets(hasUltraWide: hasUltraWide, switchOver: switchOver, maxDisplay: maxRawZoom / baseZoom)
        zoom = device.videoZoomFactor / baseZoom

        zoomObservation = device.observe(\.videoZoomFactor, options: [.new]) { [weak self] dev, _ in
            DispatchQueue.main.async { guard let self else { return }; self.zoom = dev.videoZoomFactor / self.baseZoom }
        }
        // After a tap-to-focus, return to continuous autofocus once the scene changes.
        subjectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resetFocus() }
        }
    }

    deinit {
        zoomObservation?.invalidate()
        if let o = subjectObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Zoom

    /// Smoothly animate to a preset, the way tapping a lens button does in the native app.
    func ramp(toDisplay display: CGFloat) {
        guard let device else { return }
        let target = min(max(display * baseZoom, device.minAvailableVideoZoomFactor), maxRawZoom)
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.cancelVideoZoomRamp()
        device.ramp(toVideoZoomFactor: target, withRate: 5)
        device.unlockForConfiguration()
    }

    func pinchChanged(scale: CGFloat) {
        guard let device else { return }
        if !pinching {
            pinching = true
            pinchStartRaw = device.videoZoomFactor
            if (try? device.lockForConfiguration()) != nil { device.cancelVideoZoomRamp(); device.unlockForConfiguration() }
        }
        let target = min(max(pinchStartRaw * scale, device.minAvailableVideoZoomFactor), maxRawZoom)
        if (try? device.lockForConfiguration()) != nil { device.videoZoomFactor = target; device.unlockForConfiguration() }
    }

    func pinchEnded() { pinching = false }

    // MARK: - Focus and exposure

    /// Tap to focus and meter at a point in the preview's coordinates; a new tap starts from neutral exposure.
    func focus(at layerPoint: CGPoint) {
        guard let device, let layer = previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = .autoExpose
        }
        device.setExposureTargetBias(0)
        exposureBias = 0
        device.unlockForConfiguration()
        focusProxy.view?.show(at: layerPoint)
    }

    /// Drag up or down shortly after a tap to brighten or darken, like the native Camera (about 100 pt per EV).
    func dragExposure(translationY: CGFloat) {
        guard let device, focusProxy.view?.isActive == true else { return }
        let start = dragStartBias ?? exposureBias
        dragStartBias = start
        let bias = min(max(start - Float(translationY) / 100, -2), 2)
        let clamped = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
        if (try? device.lockForConfiguration()) != nil { device.setExposureTargetBias(clamped); device.unlockForConfiguration() }
        exposureBias = clamped
        focusProxy.view?.setBias(clamped)
    }

    func dragEnded() { dragStartBias = nil }

    private func resetFocus() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            device.exposureMode = .continuousAutoExposure
        }
        device.setExposureTargetBias(0)
        exposureBias = 0
        device.unlockForConfiguration()
    }
}

/// Lets SwiftUI-side code drive the UIKit focus square.
final class FocusSquareProxy {
    weak var view: FocusSquare?
}

/// The yellow focus square (with its exposure sun), laid over the whole preview.
struct FocusSquareOverlay: UIViewRepresentable {
    let proxy: FocusSquareProxy

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.isUserInteractionEnabled = false
        host.backgroundColor = .clear
        let square = FocusSquare()
        host.addSubview(square)
        proxy.view = square
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The native-style lens buttons ("0.5 1× 2 5").
struct ZoomBarView: UIViewRepresentable {
    let presets: [CGFloat]
    let zoom: CGFloat
    let pinching: Bool
    let onSelect: (CGFloat) -> Void

    func makeUIView(context: Context) -> ZoomBar {
        let bar = ZoomBar()
        bar.onSelect = onSelect
        return bar
    }

    func updateUIView(_ bar: ZoomBar, context: Context) {
        bar.onSelect = onSelect
        bar.hapticsEnabled = pinching
        if bar.presets != presets { bar.configure(presets: presets) }
        if !presets.isEmpty { bar.update(current: zoom) }
    }
}
