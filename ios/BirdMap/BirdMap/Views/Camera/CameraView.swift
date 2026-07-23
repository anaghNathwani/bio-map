import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct CameraView: View {
    @StateObject private var vm = CameraViewModel()
    @State private var showPicker = false
    @State private var showBirdInfo = false
    @State private var visionCandidates: [APIClient.VisionCandidate] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let img = vm.capturedImage {
                    capturedImageSection(img)
                } else {
                    emptyStateSection
                }

                captureButtons
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .onAppear { vm.startLocationUpdates() }
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
        .alert("Sighting Submitted!", isPresented: $vm.uploadSuccess) {
            Button("Great!") {}
        } message: {
            Text("Your sighting has been added to the map and queued for community annotation.")
        }
    }

    private func fetchVisionCandidates(_ img: UIImage) async {
        guard let data = img.jpegData(compressionQuality: 0.7) else { return }
        visionCandidates = (try? await APIClient.shared.identifyImage(imageData: data)) ?? []
    }

    @ViewBuilder
    private func capturedImageSection(_ img: UIImage) -> some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

                if let suggestion = vm.aiSuggestion {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .symbolRenderingMode(.multicolor)
                        Text("**\(suggestion.species)**")
                        Text("· \(Int(suggestion.confidence * 100))%")
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Button("Learn More") { showBirdInfo = true }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal.opacity(0.8), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(14)
                }

                // Google Vision candidates
                if !visionCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Google Vision suggestions", systemImage: "eye.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        ForEach(visionCandidates.prefix(3), id: \.species) { c in
                            HStack {
                                Text(c.species).font(.caption)
                                Spacer()
                                Text("\(Int(c.confidence * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                TextField("Notes (optional)", text: $vm.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                if let error = vm.error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                Button {
                    Task { await vm.upload() }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isUploading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .symbolEffect(.bounce, value: vm.isUploading)
                        }
                        Text(vm.isUploading ? "Uploading…" : "Submit Sighting")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.isUploading ? Color.gray : Color.teal, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(vm.isUploading)
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.2), value: vm.isUploading)
            }
        }
    }

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(
                        colors: [Color.teal.opacity(0.13), Color.teal.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .proportionalHeight(0.34, min: 200, max: 320)

                VStack(spacing: 14) {
                    let iconSize = ScreenSize.current.scale(60, compact: 46, large: 68)
                    Image(systemName: "bird")
                        .font(.system(size: iconSize))
                        .foregroundStyle(Color.teal.opacity(0.65))
                        .symbolEffect(.pulse)
                    Text("No Photo Yet")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("Take a photo or choose from your library\nto identify and report a sighting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .padding(.horizontal)
        }
    }

    private var captureButtons: some View {
        HStack(spacing: 12) {
            Button {
                showPicker = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                    Text("Library")
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .foregroundStyle(.primary)

            NavigationLink {
                LiveCameraView(vm: vm, onVisionResults: { candidates in
                    visionCandidates = candidates
                })
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                    Text("Camera")
                        .font(.caption.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.teal, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
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
    var onVisionResults: (([APIClient.VisionCandidate]) -> Void)?

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

        var onVisionResults: (([APIClient.VisionCandidate]) -> Void)?

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
        b.tintColor = .white
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
