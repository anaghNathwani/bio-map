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
        .background(ThemeColors(scheme: scheme).paper)
        .onAppear {
            vm.startLocationUpdates()
            // BirdRadarApp only ever tries this once, at cold launch, with no
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
                            .foregroundStyle(c.paper.opacity(0.75))
                        Spacer()
                        Button("Learn more") { showBirdInfo = true }
                            .font(Theme.sansSemibold(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(c.paper.opacity(0.16), in: Capsule())
                            .overlay(Capsule().strokeBorder(c.paper.opacity(0.4), lineWidth: 1))
                    }
                    .foregroundStyle(c.paper)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(c.ink.opacity(0.88), in: Capsule())
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
                        .foregroundStyle(c.paper)
                        .frame(width: 40, height: 40)
                        .background(c.ink.opacity(0.72), in: Circle())
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
                    .background(ThemeColors(scheme: scheme).paperDim, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)

                if let error = vm.error {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(Theme.sans(13))
                    .foregroundStyle(ThemeColors(scheme: scheme).clay)
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
                .buttonStyle(ClayButtonStyle())
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
                    Text(species).font(Theme.sans(14)).foregroundStyle(c.ink)
                    Spacer()
                    Text("\(Int(confidence * 100))%")
                        .font(Theme.sansMedium(13))
                        .foregroundStyle(c.inkSoft)
                }
            }
        }
        .padding(14)
        .background(c.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
        .padding(.horizontal)
    }

    private var noModelBanner: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").foregroundStyle(c.clay)
            VStack(alignment: .leading, spacing: 2) {
                Text("On-device model not yet downloaded").font(Theme.sansSemibold(13)).foregroundStyle(c.ink)
                Text("You can still report this sighting — it just won't get an on-device AI suggestion.")
                    .font(Theme.sans(12))
                    .foregroundStyle(c.inkSoft)
            }
            Spacer()
            if isCheckingForModel {
                ProgressView().scaleEffect(0.8).tint(c.clay)
            } else {
                Button("Retry", action: retryModelDownload)
                    .font(Theme.sansSemibold(13))
                    .foregroundStyle(c.clay)
            }
        }
        .padding(12)
        .background(c.claySoft.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
    }

    private var notConfidentBanner: some View {
        let c = ThemeColors(scheme: scheme)
        return HStack(spacing: 10) {
            Image(systemName: "questionmark.circle").foregroundStyle(c.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't confidently identify a bird").font(Theme.sansSemibold(13)).foregroundStyle(c.ink)
                Text("The on-device model isn't sure this is one of the species it knows — you can still report it and add your own ID.")
                    .font(Theme.sans(12))
                    .foregroundStyle(c.inkSoft)
            }
            Spacer()
        }
        .padding(12)
        .background(c.paperDim, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .fill(c.paperDim)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(c.rule, lineWidth: 1.5))
                    .proportionalHeight(0.34, min: 200, max: 320)

                VStack(spacing: 14) {
                    let markSize = ScreenSize.current.scale(56, compact: 44, large: 64)
                    BirdMark()
                        .stroke(c.inkSoft, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: markSize, height: markSize)
                    Text("No photo yet")
                        .font(Theme.display(20, medium: true))
                        .foregroundStyle(c.ink)
                    Text("Take a photo or choose from your library\nto identify and report a sighting")
                        .font(Theme.sans(14))
                        .foregroundStyle(c.inkSoft)
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
                .foregroundStyle(c.ink)
                .background(c.paperDim, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .background(c.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(c.paper)
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

final class LiveCameraVC: UIViewController, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var preview: AVCaptureVideoPreviewLayer!
    private let coordinator: LiveCameraView.Coordinator
    private lazy var shutterButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "camera.shutter.button.fill"), for: .normal)
        b.tintColor = UIColor(red: 0.76, green: 0.54, blue: 0.35, alpha: 1)   // Theme.clay, dark scheme
        b.contentVerticalAlignment = .fill
        b.contentHorizontalAlignment = .fill
        b.addTarget(self, action: #selector(snap), for: .touchUpInside)
        return b
    }()

    init(coordinator: LiveCameraView.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)

        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        view.addSubview(shutterButton)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),
        ])

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
