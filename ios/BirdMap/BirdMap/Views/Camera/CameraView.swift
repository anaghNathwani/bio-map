import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var vm = CameraViewModel()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let img = vm.capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .padding(.horizontal)

                        if let suggestion = vm.aiSuggestion {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("AI thinks: **\(suggestion.species)** (\(Int(suggestion.confidence * 100))%)")
                            }
                            .foregroundStyle(.teal)
                            .font(.subheadline)
                        }

                        TextField("Notes (optional)", text: $vm.notes, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)

                        if let error = vm.error {
                            Text(error).foregroundStyle(.orange).font(.caption)
                        }

                        Button {
                            Task { await vm.upload() }
                        } label: {
                            Label(vm.isUploading ? "Uploading..." : "Submit Sighting", systemImage: "paperplane.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isUploading)
                        .padding(.horizontal)

                    } else {
                        ContentUnavailableView(
                            "No Photo Yet",
                            systemImage: "bird",
                            description: Text("Take a photo or choose from your library")
                        )
                        .padding(.top, 60)
                    }

                    HStack(spacing: 16) {
                        Button {
                            showPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        NavigationLink {
                            LiveCameraView(vm: vm)
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Report Sighting")
            .sheet(isPresented: $showPicker) {
                PhotoPickerView(onSelected: { vm.nothingCapture($0) })
            }
            .alert("Sighting Submitted!", isPresented: $vm.uploadSuccess) {
                Button("Great!") {}
            }
        }
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

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }
    func makeUIViewController(context: Context) -> LiveCameraVC {
        LiveCameraVC(coordinator: context.coordinator)
    }
    func updateUIViewController(_ vc: LiveCameraVC, context: Context) {}

    final class Coordinator: NSObject {
        let vm: CameraViewModel
        init(vm: CameraViewModel) { self.vm = vm }

        func captured(_ image: UIImage) {
            vm.nothingCapture(image)
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
        b.setImage(UIImage(systemName: "circle.fill"), for: .normal)
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
            shutterButton.widthAnchor.constraint(equalToConstant: 70),
            shutterButton.heightAnchor.constraint(equalToConstant: 70),
        ])

        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
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
