import SwiftUI
import AVFoundation

/// ISBN barcode scanner view using AVFoundation
struct ScannerView: View {
    let onISBNScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = ScannerViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                // Camera preview
                CameraPreviewView(session: viewModel.session)
                    .ignoresSafeArea()

                // Scan area overlay
                scanAreaOverlay

                // Status bar
                VStack {
                    HStack {
                        if viewModel.isScanning {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundStyle(.white)
                            Text("对准图书 ISBN 条形码")
                                .font(.headline)
                                .foregroundStyle(.white)
                        } else if let error = viewModel.error {
                            Text(error)
                                .font(.headline)
                                .foregroundStyle(.red)
                                .padding(12)
                                .background(Color.black.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))

                    Spacer()
                }
            }
            .navigationTitle("扫码录入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Toggle("闪光灯", isOn: $viewModel.torchOn)
                        .labelStyle(.iconOnly)
                }
            }
            .onAppear { viewModel.startScanning(onISBNScanned: onISBNScanned) }
            .onDisappear { viewModel.stopScanning() }
        }
    }

    // MARK: - Scan Area Overlay

    private var scanAreaOverlay: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.6
            let rect = CGRect(
                x: (geometry.size.width - size) / 2,
                y: (geometry.size.height - size) / 2,
                width: size,
                height: size * 0.5 // Wider for barcode
            )

            // Dimmed background
            Color.black.opacity(0.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                )
                .overlay(
                    // Cut out the scan area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()

            // Corner brackets
            ScanCornerView()
                .frame(width: rect.width + 20, height: rect.height + 20)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.layer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.layer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var layer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Scan Corner View

struct ScanCornerView: View {
    let cornerLength: CGFloat = 20
    let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            // Top-left
            Path { path in
                path.move(to: CGPoint(x: 0, y: cornerLength))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))
            }
            .stroke(Color.accentColor, lineWidth: lineWidth)

            // Top-right
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: cornerLength))
            }
            .stroke(Color.accentColor, lineWidth: lineWidth)
            .offset(x: -cornerLength, y: 0)

            // Bottom-left
            Path { path in
                path.move(to: CGPoint(x: 0, y: -cornerLength))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))
            }
            .stroke(Color.accentColor, lineWidth: lineWidth)
            .offset(x: 0, y: cornerLength)

            // Bottom-right
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: 0))
                path.addLine(to: CGPoint(x: cornerLength, y: cornerLength))
            }
            .stroke(Color.accentColor, lineWidth: lineWidth)
            .offset(x: -cornerLength, y: cornerLength)
        }
    }
}

// MARK: - Scanner ViewModel

@MainActor
final class ScannerViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    @Published var isScanning = false
    @Published var error: String?
    @Published var torchOn = false {
        didSet {
            toggleTorch()
        }
    }

    private var onISBNScanned: ((String) -> Void)?
    private var lastScannedCode: String?
    private var lastScanTime: Date = .distantPast

    func startScanning(onISBNScanned: @escaping (String) -> Void) {
        self.onISBNScanned = onISBNScanned

        guard session.inputs.isEmpty, !session.isRunning else { return }

        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    Task { @MainActor in
                        self?.setupSession()
                    }
                } else {
                    Task { @MainActor in
                        self?.error = "需要相机权限才能扫码"
                    }
                }
            }
        case .denied, .restricted:
            error = "相机权限被拒绝，请在设置中开启"
        @unknown default:
            error = "相机权限状态异常"
        }
    }

    func stopScanning() {
        session.stopRunning()
        isScanning = false
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for metadata in metadataObjects {
            guard let code = metadata as? AVMetadataMachineReadableCodeObject,
                  code.type == .ean13 || code.type == .ean8 || code.type == .upce,
                  let isbn = code.stringValue else { continue }

            // Debounce: ignore same code within 2 seconds
            let now = Date()
            if isbn == lastScannedCode && now.timeIntervalSince(lastScanTime) < 2 {
                continue
            }

            lastScannedCode = isbn
            lastScanTime = now

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            onISBNScanned?(isbn)
            break
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            error = "无法访问摄像头"
            return
        }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.ean13, .ean8, .upce]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isScanning = true
            }
        }
    }

    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Ignore
        }
    }
}

#Preview {
    ScannerView(onISBNScanned: { _ in })
}
