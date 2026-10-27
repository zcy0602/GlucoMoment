//
//  FoodMeasurementReviewView.swift
//  GlucoMoment
//

import CoreGraphics
import simd
import SwiftUI
import UIKit

/// LiDAR 测量审核：在照片上叠加每道菜的分割区域与体积，允许修正区域、容器类型和叠放层厚。
struct FoodMeasurementReviewView: View {
    let viewModel: FoodScanViewModel

    @State private var isRefining = false
    @State private var refineIncludes = true
    @State private var draftThickness: [Int: Double] = [:]

    var body: some View {
        VStack(spacing: 16) {
            overlayCard
            itemsCard
            containersCard
            layersCard

            Button {
                viewModel.confirmMeasurements()
            } label: {
                Label("确认份量并估算营养", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.measurementOutput == nil || viewModel.isRecomputingMeasurement)
        }
    }

    // MARK: - 照片与遮罩

    private var overlayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LiDAR 实测份量", systemImage: "cube.transparent")
                    .font(.headline)
                Spacer()
                if viewModel.isRecomputingMeasurement {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let photoData = viewModel.selectedPhotoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        GeometryReader { proxy in
                            overlayContent(size: proxy.size)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("餐食照片与菜品分割区域")
                    .accessibilityHint(isRefining ? "点按照片修正选中菜品的区域" : "点按照片选中菜品")
            }

            Toggle(isOn: $isRefining.animation(.snappy)) {
                Label("点按修正区域", systemImage: "hand.tap")
            }

            if isRefining {
                Picker("修正方式", selection: $refineIncludes) {
                    Text("加入选中菜品").tag(true)
                    Text("移出选中菜品").tag(false)
                }
                .pickerStyle(.segmented)

                Text("先在下方选中一道菜，再点按照片上需要加入或移出的位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let method = viewModel.segmentationMethod {
                Text("分割方式：\(method.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func overlayContent(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let output = viewModel.measurementOutput,
               let overlay = FoodLabelOverlayRenderer.image(
                for: output.overlay,
                colors: colorTable,
                highlighted: viewModel.selectedItemIndex.map(Int32.init)
               ) {
                Image(decorative: overlay, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: size.width, height: size.height)

                ForEach(viewModel.detection?.items ?? []) { item in
                    if let centroid = output.labelCentroids[Int32(item.index)],
                       let measurement = viewModel.measurement(for: item.index) {
                        Text("\(item.name) \(Int(measurement.volumeMilliliters.rounded()))ml")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .position(x: CGFloat(centroid.x) * size.width, y: CGFloat(centroid.y) * size.height)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard size.width > 0, size.height > 0 else { return }
            let point = SIMD2(Float(location.x / size.width), Float(location.y / size.height))
            if isRefining {
                viewModel.refineSelectedItem(at: point, include: refineIncludes)
            } else {
                viewModel.selectItem(at: point)
            }
        }
    }

    // MARK: - 菜品列表

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("菜品")
                .font(.headline)

            ForEach(viewModel.detection?.items ?? []) { item in
                Button {
                    viewModel.selectedItemIndex = item.index
                } label: {
                    itemRow(item)
                }
                .buttonStyle(.plain)
            }

            if let index = viewModel.selectedItemIndex, let notes = viewModel.measurement(for: index)?.notes, !notes.isEmpty {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func itemRow(_ item: FoodDetectedItem) -> some View {
        let isSelected = viewModel.selectedItemIndex == item.index
        return HStack(spacing: 12) {
            Circle()
                .fill(FoodLabelOverlayRenderer.color(for: item.index))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                if let measurement = viewModel.measurement(for: item.index) {
                    Text(measurementText(measurement))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandTeal)
            }
        }
        .padding(10)
        .background(
            isSelected ? Color.brandTeal.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func measurementText(_ measurement: FoodItemMeasurement) -> String {
        let volume = measurement.volumeMilliliters.formatted(.number.precision(.fractionLength(0)))
        let lower = measurement.measuredGramsMin.formatted(.number.precision(.fractionLength(0)))
        let upper = measurement.measuredGramsMax.formatted(.number.precision(.fractionLength(0)))
        return "约 \(volume) ml · \(lower)～\(upper) g · \(measurement.densitySource.label)"
    }

    // MARK: - 容器

    @ViewBuilder
    private var containersCard: some View {
        let containers = viewModel.detection?.containers ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("容器")
                .font(.headline)

            if containers.isEmpty {
                Text("未识别到容器，按桌面为底计算体积。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(containers) { container in
                    Picker(selection: Binding(
                        get: { viewModel.containerType(for: container.index) },
                        set: { viewModel.setContainerType($0, for: container.index) }
                    )) {
                        ForEach(FoodContainerType.allCases) { type in
                            Label(type.label, systemImage: type.systemImage).tag(type)
                        }
                    } label: {
                        Text(containerTitle(container))
                    }
                }

                Text("碗口尺寸由 LiDAR 测得，碗底形状按所选容器类型推算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func containerTitle(_ container: FoodDetectedContainer) -> String {
        let names = (viewModel.detection?.items ?? [])
            .filter { $0.containerIndex == container.index }
            .map(\.name)
        guard let geometry = viewModel.measurementOutput?.containers[container.index] else {
            return names.isEmpty ? "容器" : names.joined(separator: "、")
        }
        let diameter = (Double(geometry.rimRadius) * 200).formatted(.number.precision(.fractionLength(0)))
        let title = names.isEmpty ? "容器" : names.joined(separator: "、")
        return "\(title)（口径约 \(diameter) cm）"
    }

    // MARK: - 叠放

    @ViewBuilder
    private var layersCard: some View {
        let layeredItems = (viewModel.detection?.items ?? []).filter { $0.layeredOnIndex != nil }
        if !layeredItems.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("叠放")
                    .font(.headline)

                ForEach(layeredItems) { item in
                    layerRow(item)
                }

                Text("上层食物的厚度决定了重叠区域的体积如何在上下层之间分配。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func layerRow(_ item: FoodDetectedItem) -> some View {
        let underName = item.layeredOnIndex.flatMap { viewModel.detection?.item(index: $0)?.name } ?? "其他食物"
        let value = draftThickness[item.index] ?? viewModel.layerThickness(for: item.index)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(item.name) 铺在\(underName)上")
                    .font(.subheadline)
                Spacer()
                Text("厚 \(value.formatted(.number.precision(.fractionLength(1)))) cm")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // 拖动时只更新草稿，松手后再重算，避免频繁计算。
            Slider(
                value: Binding(
                    get: { draftThickness[item.index] ?? viewModel.layerThickness(for: item.index) },
                    set: { draftThickness[item.index] = $0 }
                ),
                in: 0.2...5,
                step: 0.1
            ) {
                Text("\(item.name) 厚度")
            } onEditingChanged: { isEditing in
                guard !isEditing, let committed = draftThickness[item.index] else { return }
                viewModel.setLayerThickness(committed, for: item.index)
                draftThickness[item.index] = nil
            }
        }
    }

    private var colorTable: [Int32: FoodLabelOverlayRenderer.RGB] {
        (viewModel.detection?.items ?? []).reduce(into: [:]) { table, item in
            table[Int32(item.index)] = FoodLabelOverlayRenderer.rgb(for: item.index)
        }
    }
}

/// 把标签栅格渲染成半透明彩色遮罩。
enum FoodLabelOverlayRenderer {
    struct RGB: Hashable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private static let palette: [RGB] = [
        RGB(red: 0, green: 168, blue: 150),
        RGB(red: 255, green: 149, blue: 0),
        RGB(red: 255, green: 55, blue: 95),
        RGB(red: 88, green: 86, blue: 214),
        RGB(red: 52, green: 199, blue: 89),
        RGB(red: 255, green: 204, blue: 0),
        RGB(red: 175, green: 82, blue: 222),
        RGB(red: 0, green: 122, blue: 255),
        RGB(red: 162, green: 132, blue: 94),
        RGB(red: 50, green: 173, blue: 230)
    ]

    static func rgb(for index: Int) -> RGB {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    static func color(for index: Int) -> Color {
        let rgb = rgb(for: index)
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    static func image(for raster: FoodLabelRaster, colors: [Int32: RGB], highlighted: Int32?) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: raster.width * raster.height * 4)
        for row in 0..<raster.height {
            for column in 0..<raster.width {
                let label = raster.labels[row * raster.width + column]
                guard label >= 0, let rgb = colors[label] else { continue }
                // 预乘 alpha；选中的菜品更醒目。
                let alpha: Float = label == highlighted ? 0.62 : 0.38
                let offset = (row * raster.width + column) * 4
                pixels[offset] = UInt8(Float(rgb.red) * alpha)
                pixels[offset + 1] = UInt8(Float(rgb.green) * alpha)
                pixels[offset + 2] = UInt8(Float(rgb.blue) * alpha)
                pixels[offset + 3] = UInt8(255 * alpha)
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: raster.width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
