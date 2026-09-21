import PencilKit
import SwiftUI
import UIKit

// MARK: - 控制器（持有 canvas 引用，便于保存 / 撤销）

final class AnnotationController: ObservableObject {
    weak var canvasView: PKCanvasView?
    @Published var canUndo = false
    @Published var canRedo = false

    func undo() {
        canvasView?.undoManager?.undo()
        refresh()
    }

    func redo() {
        canvasView?.undoManager?.redo()
        refresh()
    }

    func clear() {
        canvasView?.drawing = PKDrawing()
        refresh()
    }

    func refresh() {
        guard let manager = canvasView?.undoManager else { return }
        canUndo = manager.canUndo
        canRedo = manager.canRedo
    }
}

// MARK: - PencilKit 画布

private struct PKCanvas: UIViewRepresentable {
    let anchor: String
    let initialDrawing: PKDrawing
    let controller: AnnotationController
    let tool: PKTool
    var onSave: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSave: onSave)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = initialDrawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.alwaysBounceVertical = false
        canvas.delegate = context.coordinator
        canvas.tool = tool
        context.coordinator.canvas = canvas
        context.coordinator.anchor = anchor
        controller.canvasView = canvas
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onSave = onSave
        uiView.tool = tool
        if context.coordinator.anchor != anchor {
            context.coordinator.flush()
            uiView.drawing = initialDrawing
            context.coordinator.anchor = anchor
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.flush()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onSave: (PKDrawing) -> Void
        weak var canvas: PKCanvasView?
        var anchor: String = ""

        init(onSave: @escaping (PKDrawing) -> Void) {
            self.onSave = onSave
        }

        func flush() {
            guard let canvas, !canvas.drawing.bounds.isEmpty else { return }
            onSave(canvas.drawing)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onSave(canvasView.drawing)
        }
    }
}

// MARK: - 手写涂鸦层

struct AnnotationCanvasView: View {
    @ObservedObject var vm: ReaderViewModel
    @StateObject private var controller = AnnotationController()

    @State private var toolKind: Int = 0        // 0 钢笔 1 荧光笔 2 铅笔 3 橡皮
    @State private var lineWidth: CGFloat = 4
    @State private var inkColor: Color = .red
    @State private var showPalette = false

    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    private var currentTool: PKTool {
        let uiColor = UIColor(inkColor)
        switch toolKind {
        case 0: return PKInkingTool(.pen, color: uiColor, width: lineWidth)
        case 1: return PKInkingTool(.marker, color: uiColor.withAlphaComponent(0.4), width: lineWidth * 3)
        case 2: return PKInkingTool(.pencil, color: uiColor, width: lineWidth)
        default: return PKEraserTool(.bitmap)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PKCanvas(
                anchor: vm.drawingAnchor,
                initialDrawing: vm.annotations.drawing(for: vm.book.id, anchor: vm.drawingAnchor),
                controller: controller,
                tool: currentTool
            ) { drawing in
                vm.annotations.setDrawing(drawing, for: vm.book.id, anchor: vm.drawingAnchor)
            }
            .allowsHitTesting(true)

            drawingToolbar
        }
        .transition(.opacity)
    }

    // MARK: 工具条

    private var drawingToolbar: some View {
        VStack(spacing: 10) {
            if showPalette {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(palette, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: color == inkColor ? 3 : 0)
                                )
                                .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                                .onTapGesture { inkColor = color }
                        }
                    }
                    .padding(.horizontal)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 18) {
                Picker("工具", selection: $toolKind) {
                    Text("钢笔").tag(0)
                    Text("荧光").tag(1)
                    Text("铅笔").tag(2)
                    Text("橡皮").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Button { showPalette.toggle() } label: {
                    Image(systemName: "paintpalette.fill")
                        .foregroundColor(inkColor)
                }

                Slider(value: $lineWidth, in: 1...18)
                    .frame(width: 90)

                Button { controller.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                Button { controller.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                Button(role: .destructive) {
                    controller.clear()
                    vm.annotations.deleteDrawing(bookId: vm.book.id, anchor: vm.drawingAnchor)
                } label: {
                    Image(systemName: "trash")
                }

                Button("完成") {
                    controller.canvasView?.resignFirstResponder()
                    vm.annotationMode = false
                }
                .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - 涂鸦静态预览

struct DrawingPreview: View {
    let drawing: PKDrawing

    var body: some View {
        if drawing.bounds.isEmpty {
            EmptyView()
        } else {
            Image(uiImage: drawing.image(from: drawing.bounds, scale: UIScreen.main.scale))
                .resizable()
                .scaledToFit()
                .allowsHitTesting(false)
        }
    }
}
