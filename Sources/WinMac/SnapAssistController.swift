import AppKit
import CoreGraphics
import SwiftUI
import WinMacCore

@MainActor
final class SnapAssistViewModel: ObservableObject {
    @Published var candidates: [WindowCandidate] = []
    @Published var selectedIndex: Int = 0
    @Published var zoneLabel: String = ""
    @Published var remainingZoneCount: Int = 1
    @Published var hasScreenRecordingPermission: Bool = CGPreflightScreenCaptureAccess()

    var onSelect: ((WindowCandidate) -> Void)?
    var onDismiss: (() -> Void)?
    var onRequestScreenRecording: (() -> Void)?

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

            VStack(spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x2.fill")
                        .foregroundStyle(Color.cyan)
                    Text(model.zoneLabel)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if !model.hasScreenRecordingPermission {
                        Button {
                            model.onRequestScreenRecording?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.caption2)
                                Text("Activar vistas previas")
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.22), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("1-\(model.candidates.count) · Esc")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
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
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Candidate cards grid
                GeometryReader { geo in
                    let columnsCount = geo.size.width >= 600 ? 3 : (geo.size.width >= 320 ? 2 : 1)
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: columnsCount)
                    let previewHeight: CGFloat = geo.size.height >= 420 ? 132 : 96

                    ScrollView {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                                cardView(candidate: candidate, index: index, previewHeight: previewHeight)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.65), lineWidth: 1.5)
        )
    }

    private func cardView(candidate: WindowCandidate, index: Int, previewHeight: CGFloat) -> some View {
        let isHovered = hoveredID == candidate.id
        let isSelected = model.selectedIndex == index

        return Button {
            model.onSelect?(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Live window preview (or sleek icon fallback)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.28))

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
                                .frame(width: 46, height: 46)
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if index < 9 {
                        Text("\(index + 1)")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle().fill(isHovered || isSelected ? Color.cyan : Color.black.opacity(0.6))
                            )
                            .padding(7)
                    }
                }
                .frame(height: previewHeight)

                HStack(spacing: 7) {
                    Image(nsImage: candidate.appIcon)
                        .resizable()
                        .frame(width: 17, height: 17)

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
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isHovered || isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isHovered || isSelected ? Color.cyan.opacity(0.95) : Color.white.opacity(0.15),
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

private struct SecondaryZoneOverlayView: View {
    let label: String
    let onActivate: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onActivate) {
            ZStack {
                FrostedBackground()
                    .opacity(isHovered ? 0.92 : 0.72)

                VStack(spacing: 8) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(isHovered ? Color.cyan : Color.white.opacity(0.75))
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Clic para elegir ventana aquí")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isHovered ? Color.cyan.opacity(0.9) : Color.white.opacity(0.28),
                        style: StrokeStyle(lineWidth: isHovered ? 2 : 1.5, dash: isHovered ? [] : [8, 6])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
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
    private var activePanel: SnapAssistPanel?
    private var secondaryPanels: [SnapAssistPanel] = []
    private let viewModel = SnapAssistViewModel()
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var thumbnailTask: Task<Void, Never>?

    private var offers: [SnapAssistOffer] = []
    private var activeOfferIndex: Int = 0
    private var allCandidates: [WindowCandidate] = []
    private var screenService: ScreenService?
    private var onPlaceWindow: ((WindowCandidate, SnapAssistOffer) -> Void)?

    var isVisible: Bool {
        activePanel?.isVisible ?? false
    }

    func present(
        offers: [SnapAssistOffer],
        candidates: [WindowCandidate],
        screenService: ScreenService,
        enumerator: WindowEnumerator,
        onPlaceWindow: @escaping (WindowCandidate, SnapAssistOffer) -> Void
    ) {
        dismiss()
        guard !offers.isEmpty, !candidates.isEmpty else { return }

        self.offers = offers
        self.activeOfferIndex = 0
        self.allCandidates = candidates
        self.screenService = screenService
        self.onPlaceWindow = onPlaceWindow

        viewModel.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        viewModel.onSelect = { [weak self] candidate in
            self?.handleCandidateSelected(candidate)
        }
        viewModel.onDismiss = { [weak self] in
            self?.dismiss()
        }
        viewModel.onRequestScreenRecording = { [weak self] in
            self?.dismiss()
            CGRequestScreenCaptureAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }

        rebuildPanels()
        installMonitors()

        // Capture live thumbnails once for the entire multi-zone session
        thumbnailTask = Task { @MainActor [weak self] in
            let thumbs = await enumerator.captureThumbnailsIfPermitted(for: candidates)
            guard let self, !Task.isCancelled, self.isVisible, !thumbs.isEmpty else { return }
            for i in self.allCandidates.indices {
                if let img = thumbs[self.allCandidates[i].key] {
                    self.allCandidates[i].thumbnail = img
                }
            }
            for i in self.viewModel.candidates.indices {
                if let img = thumbs[self.viewModel.candidates[i].key] {
                    self.viewModel.candidates[i].thumbnail = img
                }
            }
        }
    }

    func dismiss() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        removeMonitors()
        closeAllPanels()
        offers = []
        allCandidates = []
    }

    private func handleCandidateSelected(_ candidate: WindowCandidate) {
        guard offers.indices.contains(activeOfferIndex) else {
            dismiss()
            return
        }

        let chosenOffer = offers[activeOfferIndex]
        onPlaceWindow?(candidate, chosenOffer)

        // Remove filled zone & placed window; continue to next empty zone if any remain!
        offers.remove(at: activeOfferIndex)
        allCandidates.removeAll { $0.key == candidate.key }

        if offers.isEmpty || allCandidates.isEmpty {
            dismiss()
            return
        }

        activeOfferIndex = min(activeOfferIndex, offers.count - 1)
        rebuildPanels()
    }

    private func switchActiveOffer(to index: Int) {
        guard offers.indices.contains(index), index != activeOfferIndex else { return }
        activeOfferIndex = index
        rebuildPanels()
    }

    private func rebuildPanels() {
        closeAllPanels()
        guard let screenService, offers.indices.contains(activeOfferIndex) else { return }

        let activeOffer = offers[activeOfferIndex]
        viewModel.candidates = allCandidates
        viewModel.selectedIndex = min(viewModel.selectedIndex, max(0, allCandidates.count - 1))
        viewModel.zoneLabel = Self.label(for: activeOffer.targetState)
        viewModel.remainingZoneCount = offers.count
        viewModel.hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

        // 1. Secondary empty-zone panels (for all other empty quarters)
        for (idx, offer) in offers.enumerated() where idx != activeOfferIndex {
            let cocoaFrame = screenService.axToCocoa(offer.targetFrame).insetBy(dx: 12, dy: 12)
            guard cocoaFrame.width >= 160, cocoaFrame.height >= 140 else { continue }

            let view = SecondaryZoneOverlayView(label: Self.shortLabel(for: offer.targetState)) { [weak self] in
                self?.switchActiveOffer(to: idx)
            }
            let panel = makePanel(frame: cocoaFrame, rootView: AnyView(view))
            panel.orderFront(nil)
            secondaryPanels.append(panel)
        }

        // 2. Active picker panel
        let activeCocoaFrame = screenService.axToCocoa(activeOffer.targetFrame).insetBy(dx: 12, dy: 12)
        guard activeCocoaFrame.width >= 200, activeCocoaFrame.height >= 180 else { return }
        let mainPanel = makePanel(frame: activeCocoaFrame, rootView: AnyView(SnapAssistOverlayView(model: viewModel)))
        mainPanel.makeKeyAndOrderFront(nil)
        activePanel = mainPanel
    }

    private func makePanel(frame: CGRect, rootView: AnyView) -> SnapAssistPanel {
        let hosting = NSHostingController(rootView: rootView)
        let panel = SnapAssistPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.setFrame(frame, display: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
        return panel
    }

    private func closeAllPanels() {
        activePanel?.orderOut(nil)
        activePanel = nil
        for panel in secondaryPanels {
            panel.orderOut(nil)
        }
        secondaryPanels.removeAll()
    }

    private func allOpenPanels() -> [SnapAssistPanel] {
        (activePanel.map { [$0] } ?? []) + secondaryPanels
    }

    private func installMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                let mouse = NSEvent.mouseLocation
                let clickedInsideAnyPanel = self.allOpenPanels().contains { $0.frame.contains(mouse) }
                if !clickedInsideAnyPanel {
                    self.dismiss()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            if event.modifierFlags.contains([.control, .option]) {
                self.dismiss()
                return event
            }

            switch event.keyCode {
            case 53: // Escape
                self.dismiss()
                return nil
            case 48: // Tab -> cycle active empty zone!
                if self.offers.count > 1 {
                    self.switchActiveOffer(to: (self.activeOfferIndex + 1) % self.offers.count)
                }
                return nil
            case 36, 76: // Return / Enter
                self.viewModel.selectCurrent()
                return nil
            case 123: // Left
                self.viewModel.moveSelection(delta: -1)
                return nil
            case 124: // Right
                self.viewModel.moveSelection(delta: 1)
                return nil
            case 126: // Up
                self.viewModel.moveSelection(delta: -2)
                return nil
            case 125: // Down
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
        case .leftHalf: return "Mitad izquierda"
        case .rightHalf: return "Mitad derecha"
        case .topLeftQuarter: return "Esquina superior izquierda"
        case .bottomLeftQuarter: return "Esquina inferior izquierda"
        case .topRightQuarter: return "Esquina superior derecha"
        case .bottomRightQuarter: return "Esquina inferior derecha"
        case .floating, .maximized: return "Elegir ventana"
        }
    }

    private static func shortLabel(for state: SnapState) -> String {
        switch state {
        case .leftHalf: return "Mitad izquierda"
        case .rightHalf: return "Mitad derecha"
        case .topLeftQuarter: return "Superior izquierda"
        case .bottomLeftQuarter: return "Inferior izquierda"
        case .topRightQuarter: return "Superior derecha"
        case .bottomRightQuarter: return "Inferior derecha"
        case .floating, .maximized: return "Espacio libre"
        }
    }
}
