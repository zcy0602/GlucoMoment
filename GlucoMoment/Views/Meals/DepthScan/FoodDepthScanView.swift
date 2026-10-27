//
//  FoodDepthScanView.swift
//  GlucoMoment
//

import ARKit
import RealityKit
import SwiftUI
import UIKit

/// 全屏 LiDAR 扫描界面：锁定桌面后，用户在餐食上方缓慢移动 2～3 秒完成扫描。
struct FoodDepthScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scanSession = FoodDepthScanSession()

    let onCapture: (FoodDepthCapture) -> Void
    let onUseRegularCamera: () -> Void

    var body: some View {
        ZStack {
            DepthScanCameraView(scanSession: scanSession)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                Spacer()
                guidanceCard
                controls
            }
            .padding()
        }
        .background(.black)
        .onDisappear {
            scanSession.pause()
        }
        .onChange(of: scanSession.phase) { _, phase in
            guard phase == .finished, let capture = scanSession.capture else { return }
            onCapture(capture)
            dismiss()
        }
    }

    private var topBar: some View {
        HStack {
            Button("取消", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("取消扫描")

            Spacer()

            Button {
                dismiss()
                onUseRegularCamera()
            } label: {
                Label("普通拍照", systemImage: "camera")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .tint(.white)
    }

    private var guidanceCard: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = scanSession.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
            } else {
                Label(scanSession.guidance.message, systemImage: guidanceSymbol)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
            }

            if case .scanning = scanSession.phase {
                Text("已采集 \(scanSession.keyframeCount) 帧深度数据")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .animation(.snappy, value: scanSession.guidance)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var controls: some View {
        switch scanSession.phase {
        case .idle, .searchingSurface:
            ProgressView("正在寻找桌面…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(height: 88)
        case .ready:
            Button {
                scanSession.beginScan()
            } label: {
                Label("开始扫描", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .scanning(let progress):
            HStack(spacing: 16) {
                ScanProgressRing(progress: progress)
                Button {
                    scanSession.finishScan()
                } label: {
                    Text("完成扫描")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
                .disabled(scanSession.keyframeCount < FoodDepthScanSession.Configuration.minimumKeyframes)
            }
        case .processing, .finished:
            ProgressView("正在整理扫描数据…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(height: 88)
        case .failed:
            Button {
                scanSession.restart()
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var guidanceSymbol: String {
        switch scanSession.guidance {
        case .findSurface:
            "rectangle.dashed"
        case .aimAtFood:
            "fork.knife"
        case .moveSlower:
            "tortoise"
        case .moveCloser:
            "arrow.down.right.and.arrow.up.left"
        case .moveFarther:
            "arrow.up.left.and.arrow.down.right"
        case .improveLighting:
            "sun.max"
        case .trackingLimited:
            "location.magnifyingglass"
        case .keepScanning:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .done:
            "checkmark.circle"
        }
    }
}

private struct ScanProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brandTeal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.15), value: progress)
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
        .accessibilityElement()
        .accessibilityLabel("扫描进度")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// RealityKit 的 AR 相机预览；会话由 `FoodDepthScanSession` 自行配置。
private struct DepthScanCameraView: UIViewRepresentable {
    let scanSession: FoodDepthScanSession

    func makeUIView(context: Context) -> OrientationReportingARView {
        let view = OrientationReportingARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField,
            .disablePersonOcclusion,
            .disableGroundingShadows,
            .disableFaceMesh,
            .disableHDR
        ]
        view.onInterfaceOrientationChange = { [weak scanSession] orientation in
            scanSession?.interfaceOrientation = orientation
        }
        scanSession.attach(to: view.session)
        scanSession.start()
        return view
    }

    func updateUIView(_ uiView: OrientationReportingARView, context: Context) {}

    static func dismantleUIView(_ uiView: OrientationReportingARView, coordinator: ()) {
        uiView.session.pause()
    }
}

/// 在布局变化时上报界面方向，用于把横向的传感器图像转正。
private final class OrientationReportingARView: ARView {
    var onInterfaceOrientationChange: ((UIInterfaceOrientation) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation {
            onInterfaceOrientationChange?(orientation)
        }
    }
}
