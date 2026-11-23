import AppKit
import SwiftUI
import WinMacCore

@MainActor
final class SnapAssistViewModel: ObservableObject {
    @Published var candidates: [WindowCandidate] = []
    @Published var selectedIndex: Int = 0
    @Published var zoneLabel: String = ""

    var onSelect: ((WindowCandidate) -> Void)?
    var onDismiss: (() -> Void)?

    func selectCurrent() {
        guard candidates.indices.contains(selectedIndex) else { return }
        onSelect?(candidates[selectedIndex])
    }

    func select(number: Int) {
        let idx = number - 1
        guard candidates.indices.contains(idx) else { return }
        onSelect?(candidates[idx])
    }

    func moveSelection(delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + candidates.count) % candidates.count
    }
}

private struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct SnapAssistOverlayView: View {
    @ObservedObject var model: SnapAssistViewModel
    @State private var hoveredID: WindowKey?

    var body: some View {
        ZStack {
            FrostedBackground()

            VStack(spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x2.fill")
                        .foregroundStyle(Color.cyan)
                    Text(model.zoneLabel)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text("1-\(model.candidates.count) · Esc")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.6), in: Capsule())

                    Button {
                        model.onDismiss?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Candidate cards grid
                GeometryReader { geo in
                    let columnsCount = geo.size.width >= 560 ? 3 : (geo.size.width >= 340 ? 2 : 1)
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: columnsCount)

                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                                cardView(candidate: candidate, index: index)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
    }

    private func cardView(candidate: WindowCandidate, index: Int) -> some View {
        let isHovered = hoveredID == candidate.id
        let isSelected = model.selectedIndex == index

        return Button {
            model.onSelect?(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Preview area (live thumbnail if available, else sleek app icon tile)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.25))

                    if let thumb = candidate.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(4)
                    } else {
                        VStack(spacing: 6) {
                            Image(nsImage: candidate.appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Shortcut number pill
                    if index < 9 {
                        Text("\(index + 1)")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle().fill(isHovered || isSelected ? Color.cyan : Color.black.opacity(0.55))
                            )
                            .padding(8)
                    }
                }
                .frame(height: 112)

                // Footer: App Icon + Title
                HStack(spacing: 8) {
                    Image(nsImage: candidate.appIcon)
                        .resizable()
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(candidate.appName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if candidate.title != candidate.appName {
                            Text(candidate.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isHovered || isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isHovered || isSelected ? Color.cyan.opacity(0.9) : Color.white.opacity(0.14),
                        lineWidth: isHovered || isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? candidate.id : nil
            if hovering {
                model.selectedIndex = index
            }
        }
    }
}

private final class SnapAssistPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SnapAssistController {
    private var panel: SnapAssistPanel?
    private let viewModel = SnapAssistViewModel()
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var thumbnailTask: Task<Void, Never>?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func present(
        offer: SnapAssistOffer,
        cocoaFrame: CGRect,
        candidates: [WindowCandidate],
        enumerator: WindowEnumerator,
        onSelect: @escaping (WindowCandidate, SnapAssistOffer) -> Void
    ) {
        dismiss()
        guard !candidates.isEmpty else { return }

        viewModel.candidates = candidates
        viewModel.selectedIndex = 0
        viewModel.zoneLabel = Self.label(for: offer.targetState)
        viewModel.onSelect = { [weak self] candidate in
            self?.dismiss()
            onSelect(candidate, offer)
        }
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }

        let insetFrame = cocoaFrame.insetBy(dx: 12, dy: 12)
        guard insetFrame.width >= 200, insetFrame.height >= 180 else { return }

        let hosting = NSHostingController(rootView: SnapAssistOverlayView(model: viewModel))
        let panel = SnapAssistPanel(
            contentRect: insetFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.setFrame(insetFrame, display: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1.0
        }

        self.panel = panel
        installMonitors()

        // Load live thumbnails asynchronously if Screen Recording permission is already granted
        thumbnailTask = Task { @MainActor [weak self] in
            let thumbs = await enumerator.captureThumbnailsIfPermitted(for: candidates)
            guard let self, !Task.isCancelled, self.isVisible, !thumbs.isEmpty else { return }
            for i in self.viewModel.candidates.indices {
                let key = self.viewModel.candidates[i].key
                if let img = thumbs[key] {
                    self.viewModel.candidates[i].thumbnail = img
                }
            }
        }
    }

    func dismiss() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        removeMonitors()
        if let panel {
            panel.orderOut(nil)
            self.panel = nil
        }
    }

    private func installMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            // Let Control+Option shortcuts pass through to Carbon HotkeyManager
            if event.modifierFlags.contains([.control, .option]) {
                self.dismiss()
                return event
            }

            switch event.keyCode {
            case 53: // Escape
                self.dismiss()
                return nil
            case 36, 76: // Return / Enter
                self.viewModel.selectCurrent()
                return nil
            case 123: // Left arrow
                self.viewModel.moveSelection(delta: -1)
                return nil
            case 124: // Right arrow
                self.viewModel.moveSelection(delta: 1)
                return nil
            case 126: // Up arrow
                self.viewModel.moveSelection(delta: -2)
                return nil
            case 125: // Down arrow
                self.viewModel.moveSelection(delta: 2)
                return nil
            default:
                if let chars = event.charactersIgnoringModifiers,
                   let num = Int(chars), (1...9).contains(num) {
                    self.viewModel.select(number: num)
                    return nil
                }
                return event
            }
        }
    }

    private func removeMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private static func label(for state: SnapState) -> String {
        switch state {
        case .leftHalf: return "Colocar en mitad izquierda"
        case .rightHalf: return "Colocar en mitad derecha"
        case .topLeftQuarter: return "Colocar en esquina superior izquierda"
        case .bottomLeftQuarter: return "Colocar en esquina inferior izquierda"
        case .topRightQuarter: return "Colocar en esquina superior derecha"
        case .bottomRightQuarter: return "Colocar en esquina inferior derecha"
        case .floating, .maximized: return "Elegir ventana"
        }
    }
}
