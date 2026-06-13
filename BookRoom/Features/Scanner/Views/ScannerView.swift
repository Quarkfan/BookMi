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
                CameraPreviewView(session: viewModel.session)
                    .ignoresSafeArea()

                // Scan area overlay
                if viewModel.isScanning {
                    scanAreaOverlay
                } else {
                    scannerLoadingView
                }

                // Status bar
                VStack {
                    HStack {
                        if viewModel.isScanning {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundStyle(.white)
                            Text(viewModel.statusMessage)
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

    private var scannerLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text(viewModel.error ?? "正在唤醒相机...")
                .font(.headline)
                .foregroundStyle(viewModel.error == nil ? .white : .red)
        }
        .padding(18)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
    }

    private var scanAreaOverlay: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.6
            let rect = CGRect(
                x: (geometry.size.width - size) / 2,
                y: (geometry.size.height - size) / 2,
                width: size,
                height: size * 0.5 // Wider for barcode
            )

            // Keep the camera image visible; a heavy cutout mask can look like a gray screen on device.
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            // Corner brackets
            ScanCornerView()
                .frame(width: rect.width + 20, height: rect.height + 20)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

            VStack(spacing: 6) {
                Text("扫描 ISBN 条形码")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("把书背面的条形码放进取景框")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .position(x: geometry.size.width / 2, y: rect.maxY + 54)

            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PreviewView else { return }
        view.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
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

final class ScannerViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published var isScanning = false
    @Published var error: String?
    @Published var statusMessage = "对准图书 ISBN 条形码"
    @Published var torchOn = false {
        didSet {
            toggleTorch()
        }
    }

    private var onISBNScanned: ((String) -> Void)?
    private let sessionQueue = DispatchQueue(label: "com.bookroom.scanner.session")
    private let metadataQueue = DispatchQueue(label: "com.bookroom.scanner.metadata")
    private var metadataOutput: AVCaptureMetadataOutput?
    private var lastScannedCode: String?
    private var lastScanTime: Date = .distantPast
    private var setupComplete = false

    func startScanning(onISBNScanned: @escaping (String) -> Void) {
        print("[Scanner] startScanning called, main: \(Thread.isMainThread)")
        self.onISBNScanned = onISBNScanned

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.setupComplete || !self.session.inputs.isEmpty {
                self.restartSessionIfNeeded()
                return
            }

            self.doSetupSession()
        }
    }

    private func doSetupSession() {
        // Double-check we're ready to set up
        guard !setupComplete, session.inputs.isEmpty, !session.isRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.sessionQueue.async { self?.setupSession() }
                } else {
                    DispatchQueue.main.async { self?.error = "需要相机权限才能扫码" }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.error = "相机权限被拒绝，请在设置中开启" }
        @unknown default:
            DispatchQueue.main.async { self.error = "相机权限状态异常" }
        }
    }

    func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isScanning = false
                self.statusMessage = "对准图书 ISBN 条形码"
            }
        }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for metadata in metadataObjects {
            guard let code = metadata as? AVMetadataMachineReadableCodeObject,
                  let rawValue = code.stringValue else { continue }

            let now = Date()
            if rawValue == lastScannedCode && now.timeIntervalSince(lastScanTime) < 2 {
                continue
            }

            lastScannedCode = rawValue
            lastScanTime = now

            let normalized = normalizeScannedCode(rawValue)
            let isISBN = isLikelyISBN(normalized)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if isISBN {
                    self.statusMessage = "识别到 ISBN \(normalized)，正在查询..."
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.onISBNScanned?(normalized)
                } else {
                    self.statusMessage = "识别到非 ISBN 条码：\(normalized)"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            break
        }
    }

    private func setupSession() {
        print("[Scanner] Setting up session, main thread: \(Thread.isMainThread)")

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("[Scanner] No camera device")
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = "无法访问摄像头" }
            return
        }
        print("[Scanner] Got camera device")
        configureCamera(device)

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("[Scanner] Cannot create/add input")
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = "无法访问摄像头" }
            return
        }
        session.addInput(input)
        print("[Scanner] Added input")

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            print("[Scanner] Cannot add output")
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = "无法配置扫码输出" }
            return
        }
        session.addOutput(output)
        metadataOutput = output
        print("[Scanner] Added output")

        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        let wantedTypes: [AVMetadataObject.ObjectType] = [
            .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14
        ]
        let supportedTypes = wantedTypes.filter { output.availableMetadataObjectTypes.contains($0) }
        output.metadataObjectTypes = supportedTypes
        print("[Scanner] Metadata types: \(supportedTypes)")
        session.commitConfiguration()

        // startRunning is synchronous, so keep it off the main thread to avoid freezing the sheet.
        print("[Scanner] Calling startRunning()...")
        session.startRunning()
        print("[Scanner] Session started successfully")
        setupComplete = true
        DispatchQueue.main.async {
            self.isScanning = true
            self.error = nil
            self.statusMessage = "对准图书 ISBN 条形码"
        }
    }

    private func restartSessionIfNeeded() {
        guard !session.isRunning else {
            DispatchQueue.main.async {
                self.isScanning = true
                self.error = nil
                self.statusMessage = "对准图书 ISBN 条形码"
            }
            return
        }

        print("[Scanner] Restarting existing session...")
        session.startRunning()
        setupComplete = true
        DispatchQueue.main.async {
            self.isScanning = true
            self.error = nil
            self.statusMessage = "对准图书 ISBN 条形码"
        }
    }

    private func configureCamera(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("[Scanner] Camera configuration failed: \(error)")
        }
    }

    nonisolated private func normalizeScannedCode(_ value: String) -> String {
        value
            .uppercased()
            .filter { $0.isNumber || $0 == "X" }
    }

    nonisolated private func isLikelyISBN(_ value: String) -> Bool {
        guard value.count == 10 || value.count == 13 else { return false }
        if value.count == 13 {
            return value.hasPrefix("978") || value.hasPrefix("979")
        }
        return true
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
