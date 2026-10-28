import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct CameraView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var vm = CameraViewModel()
    @State private var showPicker = false
    @State private var showBirdInfo = false
    @State private var visionCandidates: [VisionCandidate] = []
    @State private var showAIReview = false
    @State private var showAnnotate = false
    @State private var showPlainSuccess = false
    @State private var pendingVerdict: AIVerdict?
    // ModelManager.isModelAvailable isn't observable, so this view wouldn't
    // otherwise notice when a download finishes — tracked locally instead.
    @State private var modelAvailable = ModelManager.shared.isModelAvailable
    @State private var isCheckingForModel = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let img = vm.capturedImage {
                    capturedImageSection(img)
                } else {
                    emptyStateSection
                }

                captureButtons

                if let sightingID = vm.lastUploadedSightingID, !vm.lastAdditionalSuggestions.isEmpty {
                    AdditionalBirdsSection(sightingID: sightingID, candidates: vm.lastAdditionalSuggestions)
                }
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .background(ThemeColors(scheme: scheme).bg)
        .onAppear {
            vm.startLocationUpdates()
            // BioMapApp only ever tries this once, at cold launch, with no
            // retry — a single transient failure there (network not up yet,
            // etc.) would otherwise strand the app without a model forever.
            // Retrying whenever this tab appears and the model is still
            // missing makes that self-healing instead of permanent.
            if !modelAvailable { retryModelDownload() }
        }
        .onDisappear { vm.stopLocationUpdates() }
        .sheet(isPresented: $showPicker) {
            PhotoPickerView(onSelected: { img in
                vm.setImage(img)
                Task { await fetchVisionCandidates(img) }
            })
        }
        .sheet(isPresented: $showBirdInfo) {
            if let species = vm.aiSuggestion?.species {
                BirdInfoView(species: species)
            }
        }
        .onChange(of: vm.uploadSuccess) { _, success in
            guard success else { return }
            vm.uploadSuccess = false
            if vm.lastAISuggestion != nil {
                showAIReview = true
            } else {
                showPlainSuccess = true
            }
        }
        .sheet(isPresented: $showAIReview) {
            if let suggestion = vm.lastAISuggestion {
                aiReviewSheet(species: suggestion.species, confidence: Double(suggestion.confidence))
            }
        }
        .sheet(isPresented: $showAnnotate) {
            if let sightingID = vm.lastUploadedSightingID {
                AnnotationView(
                    sightingID: sightingID,
                    initialSpecies: pendingVerdict == .confirmed ? (vm.lastAISuggestion?.species ?? "") : "",
                    initialConfidence: pendingVerdict == .confirmed ? 0.95 : 0.6,
                    reviewOfAI: pendingVerdict?.reviewOfAI
                ) {
                    showAnnotate = false
                }
            }
        }
        .alert("Sighting Submitted!", isPresented: $showPlainSuccess) {
            Button("Great!") {}
        } message: {
            Text("Your sighting has been added to the map and queued for community annotation.")
        }
    }

    private func aiReviewSheet(species: String, confidence: Double) -> some View {
        VStack {
            Spacer()
            AIPredictionCard(species: species, confidence: confidence) { verdict in
                pendingVerdict = verdict
                showAIReview = false
                showAnnotate = true
            }
            Spacer()
        }
        .presentationDetents([.medium])
    }

    private func fetchVisionCandidates(_ img: UIImage) async {
        guard let data = img.jpegData(compressionQuality: 0.7) else { return }
        visionCandidates = (try? await APIClient.shared.identifyImage(imageData: data)) ?? []
    }

    @ViewBuilder
    private func capturedImageSection(_ img: UIImage) -> some View {
        let c = ThemeColors(scheme: scheme)
        VStack(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))

                if let suggestion = vm.aiSuggestion {
                    HStack(spacing: 8) {
                        Text(suggestion.species).font(Theme.sansSemibold(13))
                        Text("· \(Int(suggestion.confidence * 100))%")
                            .font(Theme.sans(13))
                            .foregroundStyle(c.bg.opacity(0.75))
                        Spacer()
                        Button("Learn more") { showBirdInfo = true }
                            .font(Theme.sansSemibold(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(c.bg.opacity(0.16), in: Capsule())
                            .overlay(Capsule().strokeBorder(c.bg.opacity(0.4), lineWidth: 1))
                    }
                    .foregroundStyle(c.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(c.fg.opacity(0.88), in: Capsule())
                    .padding(14)
                }
            }
            .overlay(alignment: .topLeading) {
                Button {
                    visionCandidates = []
                    vm.retake()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundStyle(c.bg)
                        .frame(width: 40, height: 40)
                        .background(c.fg.opacity(0.72), in: Circle())
                }
                .disabled(vm.isUploading)
                .padding(12)
                .accessibilityLabel("Retake photo")
            }
            .padding(.horizontal)

            // On-device AI candidates
            if !vm.aiCandidates.isEmpty {
                candidatesPanel(
                    title: "On-device · common birds",
                    items: vm.aiCandidates.map { ($0.species, Double($0.confidence)) }
                )
            } else if vm.capturedImage != nil && !modelAvailable {
                noModelBanner
            } else if vm.capturedImage != nil && modelAvailable && vm.didClassify {
                notConfidentBanner
            }

            // Other birds spotted via saliency-region detection, beyond the
            // primary suggestion above — confirmed/corrected after upload,
            // this is just a preview of what will be offered then.
            if !vm.aiAdditionalSuggestions.isEmpty {
                candidatesPanel(
                    title: "Also spotted in frame",
                    items: vm.aiAdditionalSuggestions.map { ($0.species, $0.confidence) }
                )
            }

            // Google Vision candidates
            if !visionCandidates.isEmpty {
                candidatesPanel(
                    title: "Google Vision",
                    items: visionCandidates.prefix(3).map { ($0.species, $0.confidence) }
                )
            }

            VStack(spacing: 12) {
                TextField("Notes (optional)", text: $vm.notes, axis: .vertical)
                    .font(Theme.sans(15))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(ThemeColors(scheme: scheme).bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)

                if let error = vm.error {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(Theme.sans(13))
                    .foregroundStyle(ThemeColors(scheme: scheme).accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                Button {
                    Task { await vm.upload() }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isUploading {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(vm.isUploading ? "Uploading…" : "Submit sighting")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(vm.isUploading)
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.2), value: vm.isUploading)
            }
        }
    }

    @ViewBuilder
    private func candidatesPanel(title: String, items: [(String, Double)]) -> some View {
        let c = ThemeColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: title)
            ForEach(items, id: \.0) { species, confidence in
                HStack {
                    Text(species).font(Theme.sans(14)).foregroundStyle(c.fg)
                    Spacer()
                    Text("\(Int(confidence * 100))%")
                        .font(Theme.sansMedium(13))
                        .foregroundStyle(c.fgSoft)
                }
            }
        }
        .padding(14)
        .background(c.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
        .padding(.horizontal)
    }

    private var noModelBanner: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(c.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("On-device model not yet downloaded").font(Theme.sansSemibold(13)).foregroundStyle(c.fg)
                Text("You can still report this sighting — it just won't get an on-device AI suggestion.")
                    .font(Theme.sans(12))
                    .foregroundStyle(c.fgSoft)
            }
            Spacer()
            if isCheckingForModel {
                ProgressView().scaleEffect(0.8).tint(c.accent)
            } else {
                Button("Retry", action: retryModelDownload)
                    .font(Theme.sansSemibold(13))
                    .foregroundStyle(c.accent)
            }
        }
        .padding(12)
        .background(c.accentSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var notConfidentBanner: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 10) {
            Image(systemName: "questionmark.circle").foregroundStyle(c.fgSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't confidently identify a bird").font(Theme.sansSemibold(13)).foregroundStyle(c.fg)
                Text("The on-device model isn't sure this is one of the species it knows — you can still report it and add your own ID.")
                    .font(Theme.sans(12))
                    .foregroundStyle(c.fgSoft)
            }
            Spacer()
        }
        .padding(12)
        .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private func retryModelDownload() {
        guard !isCheckingForModel else { return }
        isCheckingForModel = true
        Task {
            await ModelManager.shared.checkForUpdate()
            modelAvailable = ModelManager.shared.isModelAvailable
            isCheckingForModel = false
        }
    }

    private var emptyStateSection: some View {
        let c = ThemeColors(scheme: scheme)
        return VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(c.bgRaised)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
                    .proportionalHeight(0.34, min: 200, max: 320)

                VStack(spacing: 14) {
                    let markSize = ScreenSize.current.scale(56, compact: 44, large: 64)
                    BirdMark()
                        .stroke(c.fgSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: markSize, height: markSize)
                    Text("No photo yet")
                        .font(Theme.display(20, medium: true))
                        .foregroundStyle(c.fg)
                    Text("Take a photo or choose from your library\nto identify and report a sighting")
                        .font(Theme.sans(14))
                        .foregroundStyle(c.fgSoft)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .padding(.horizontal)
        }
    }

    private var captureButtons: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 12) {
            Button {
                showPicker = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "photo.stack").font(.title2)
                    Text("Library").font(Theme.sansMedium(12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(c.fg)
                .background(c.bgRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
            }

            NavigationLink {
                LiveCameraView(vm: vm, onVisionResults: { candidates in
                    visionCandidates = candidates
                })
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill").font(.title2)
                    Text("Camera").font(Theme.sansMedium(12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(c.fg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(c.bg)
            }
        }
        .padding(.horizontal)
    }
}

struct PhotoPickerView: UIViewControllerRepresentable {
    var onSelected: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelected: onSelected) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onSelected: (UIImage) -> Void
        init(onSelected: @escaping (UIImage) -> Void) { self.onSelected = onSelected }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onSelected(img) }
            picker.dismiss(animated: true)
        }
    }
}

struct LiveCameraView: UIViewControllerRepresentable {
    var vm: CameraViewModel
    var onVisionResults: (([VisionCandidate]) -> Void)?

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(vm: vm)
        c.onVisionResults = onVisionResults
        return c
    }
    func makeUIViewController(context: Context) -> LiveCameraVC {
        LiveCameraVC(coordinator: context.coordinator)
    }
    func updateUIViewController(_ vc: LiveCameraVC, context: Context) {}

    final class Coordinator: NSObject {
        let vm: CameraViewModel
        init(vm: CameraViewModel) { self.vm = vm }

        var onVisionResults: (([VisionCandidate]) -> Void)?

        func captured(_ image: UIImage) {
            Task { @MainActor in
                vm.setImage(image)
                if let data = image.jpegData(compressionQuality: 0.7),
                   let candidates = try? await APIClient.shared.identifyImage(imageData: data) {
                    onVisionResults?(candidates)
                }
            }
        }
    }
}

final class LiveCameraVC: UIViewController, AVCapturePhotoCaptureDelegate, UIGestureRecognizerDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var preview: AVCaptureVideoPreviewLayer!
    private let coordinator: LiveCameraView.Coordinator
    private let shutterButton = ShutterButton()

    // Zoom (native-camera style): lens buttons + pinch. `baseZoom` is the raw videoZoomFactor of "1×".
    private var device: AVCaptureDevice?
    private var baseZoom: CGFloat = 1
    private var maxRawZoom: CGFloat = 1
    private var pinchStartRaw: CGFloat = 1
    private let zoomBar = ZoomBar()
    private var zoomObservation: NSKeyValueObservation?
    private let focusSquare = FocusSquare()
    private var subjectAreaObserver: NSObjectProtocol?

    init(coordinator: LiveCameraView.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The multi-lens virtual camera when the phone has one (so zoom hops between real lenses like the
    /// native app does), else the plain wide camera.
    private static func bestBackCamera() -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back).devices.first
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        session.sessionPreset = .photo
        guard let device = Self.bestBackCamera(),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        self.device = device

        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        view.addSubview(shutterButton)
        shutterButton.addTarget(self, action: #selector(snap), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shutterButton.widthAnchor.constraint(equalToConstant: 76),
            shutterButton.heightAnchor.constraint(equalToConstant: 76),
        ])

        setUpZoom(device)
        setUpFocus(device)

        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    deinit {
        zoomObservation?.invalidate()
        if let o = subjectAreaObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Zoom

    private func setUpZoom(_ device: AVCaptureDevice) {
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        baseZoom = CameraZoom.base(hasUltraWide: hasUltraWide, switchOver: switchOver)
        maxRawZoom = min(device.maxAvailableVideoZoomFactor, baseZoom * CameraZoom.maxDisplayZoom)

        // Start on the main lens ("1×"), not the ultra-wide.
        try? device.lockForConfiguration()
        device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, baseZoom)
        device.unlockForConfiguration()

        zoomBar.configure(presets: CameraZoom.presets(hasUltraWide: hasUltraWide, switchOver: switchOver,
                                                      maxDisplay: maxRawZoom / baseZoom))
        zoomBar.onSelect = { [weak self] display in self?.ramp(toDisplay: display) }
        zoomBar.update(current: device.videoZoomFactor / baseZoom)
        view.addSubview(zoomBar)
        zoomBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            zoomBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomBar.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -22),
            zoomBar.heightAnchor.constraint(equalToConstant: 50),
        ])

        // Keep the bar in step with the real zoom, including while a ramp is running.
        zoomObservation = device.observe(\.videoZoomFactor, options: [.new]) { [weak self] dev, _ in
            DispatchQueue.main.async { self?.zoomBar.update(current: dev.videoZoomFactor / (self?.baseZoom ?? 1)) }
        }

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        view.addGestureRecognizer(pinch)
    }

    /// Smoothly animate to a preset, the way tapping a lens button does in the native app.
    private func ramp(toDisplay display: CGFloat) {
        guard let device else { return }
        let target = min(max(display * baseZoom, device.minAvailableVideoZoomFactor), maxRawZoom)
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.ramp(toVideoZoomFactor: target, withRate: 5)
            device.unlockForConfiguration()
        } catch {}
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard let device else { return }
        switch g.state {
        case .began:
            pinchStartRaw = device.videoZoomFactor
            zoomBar.hapticsEnabled = true
            try? device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.unlockForConfiguration()
        case .changed:
            let target = min(max(pinchStartRaw * g.scale, device.minAvailableVideoZoomFactor), maxRawZoom)
            if (try? device.lockForConfiguration()) != nil {
                device.videoZoomFactor = target
                device.unlockForConfiguration()
            }
        default:
            zoomBar.hapticsEnabled = false
        }
    }

    // MARK: - Tap to focus

    private func setUpFocus(_ device: AVCaptureDevice) {
        view.addSubview(focusSquare)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedToFocus(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
        if (try? device.lockForConfiguration()) != nil {
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        }
        // When the scene changes after a tap-to-focus, go back to continuous autofocus.
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: .main) { [weak self] _ in
            self?.resetFocus()
        }
    }

    @objc private func tappedToFocus(_ g: UITapGestureRecognizer) {
        guard let device, let preview else { return }
        let point = g.location(in: view)
        let devicePoint = preview.captureDevicePointConverted(fromLayerPoint: point)
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
            device.exposurePointOfInterest = devicePoint
            device.exposureMode = .autoExpose
        }
        device.unlockForConfiguration()
        focusSquare.show(at: point)
    }

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
        device.unlockForConfiguration()
    }

    /// Taps on the zoom bar or shutter are theirs, not a focus tap.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let v = touch.view else { return true }
        return !v.isDescendant(of: zoomBar) && !v.isDescendant(of: shutterButton)
    }

    // MARK: - Capture

    @objc private func snap() {
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        DispatchQueue.main.async {
            self.coordinator.captured(img)
            self.navigationController?.popViewController(animated: true)
        }
    }
}

#Preview {
    FirebasePreview { CameraView() }
}
