import AVFoundation
import SwiftUI
import VisionKit

enum RoomInvite {
    static func url(for id: UUID) -> String { "fuzhou-mahjong://join/\(id.uuidString)" }

    static func id(from url: URL) -> UUID? {
        guard url.scheme == "fuzhou-mahjong", url.host == "join",
              url.pathComponents.count == 2 else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

struct InviteScanner: View {
    let onInvite: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scanning = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if scanning {
                    InviteCamera(onInvite: onInvite) {
                        failed = true
                        scanning = false
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else if failed {
                    ContentUnavailableView("无法使用相机", systemImage: "qrcode.viewfinder",
                                           description: Text("你仍可从附近牌桌列表加入，或输入牌友的邀请码。"))
                } else {
                    ProgressView("正在打开相机…")
                }
            }
            .navigationTitle("扫描邀请码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .task {
            guard DataScannerViewController.isSupported else { failed = true; return }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard !Task.isCancelled else { return }
            scanning = DataScannerViewController.isAvailable
            failed = !scanning
        }
    }
}

private struct InviteCamera: UIViewControllerRepresentable {
    let onInvite: (UUID) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Delegate { Delegate(onInvite: onInvite, onFailure: onFailure) }

    func makeUIViewController(context: Context) -> Host {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return Host(scanner: scanner, onFailure: onFailure)
    }

    func updateUIViewController(_ controller: Host, context: Context) {}

    final class Delegate: NSObject, DataScannerViewControllerDelegate {
        let onInvite: (UUID) -> Void
        let onFailure: () -> Void
        private var finished = false

        init(onInvite: @escaping (UUID) -> Void, onFailure: @escaping () -> Void) {
            self.onInvite = onInvite
            self.onFailure = onFailure
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !finished else { return }
            for case .barcode(let code) in items {
                guard let payload = code.payloadStringValue, let url = URL(string: payload),
                      let id = RoomInvite.id(from: url) else { continue }
                finished = true
                scanner.stopScanning()
                onInvite(id)
                return
            }
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !finished else { return }
            finished = true
            onFailure()
        }
    }

    final class Host: UIViewController {
        let scanner: DataScannerViewController
        let onFailure: () -> Void

        init(scanner: DataScannerViewController, onFailure: @escaping () -> Void) {
            self.scanner = scanner
            self.onFailure = onFailure
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            do { try scanner.startScanning() }
            catch { onFailure() }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            scanner.stopScanning()
        }
    }
}
