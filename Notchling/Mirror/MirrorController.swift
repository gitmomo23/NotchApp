import AppKit
import AVFoundation
import Combine
import SwiftUI

final class MirrorController: ObservableObject {
    @Published var wantsPreview = false
    @Published private(set) var running = false
    @Published var message: String?

    let session = AVCaptureSession()
    var onLayoutChange: () -> Void = {}

    private let settings: SettingsStore
    private let queue = DispatchQueue(label: "notchling.camera")
    private var configured = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: .notchlingSettingsChanged,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !self.settings.mirrorEnabled {
                self.wantsPreview = false
                self.stopCapture()
                self.onLayoutChange()
            }
        }
    }

    func toggle() {
        guard settings.mirrorEnabled else { return }
        wantsPreview.toggle()
        message = nil
        if wantsPreview {
            beginCapture()
        } else {
            stopCapture()
        }
        onLayoutChange()
    }

    func panelDidExpand() {
        if wantsPreview, settings.mirrorEnabled {
            beginCapture()
        }
    }

    func panelDidCollapse() {
        stopCapture()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func stop() {
        wantsPreview = false
        stopCapture()
    }

    private func beginCapture() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            message = "Kamerazugriff wird angefragt…"
            ForegroundGate.shared.begin()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    ForegroundGate.shared.end()
                    guard let self else { return }
                    if granted {
                        self.message = nil
                        self.configureAndStart()
                    } else {
                        self.wantsPreview = false
                        self.message = "Kamerazugriff verweigert."
                        self.onLayoutChange()
                    }
                }
            }
        default:
            wantsPreview = false
            message = "Kamerazugriff verweigert."
            onLayoutChange()
        }
    }

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                    ?? AVCaptureDevice.default(for: .video)
                do {
                    if let device {
                        let input = try AVCaptureDeviceInput(device: device)
                        if self.session.canAddInput(input) {
                            self.session.addInput(input)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.message = "Keine Kamera gefunden."
                        self.wantsPreview = false
                        self.onLayoutChange()
                    }
                }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.running = self.session.isRunning
                if !self.session.isRunning {
                    self.message = "Keine Kamera gefunden."
                }
            }
        }
    }

    private func stopCapture() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.running = false
            }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
        if let connection = nsView.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
