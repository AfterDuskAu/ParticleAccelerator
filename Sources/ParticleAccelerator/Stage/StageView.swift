import AppKit
import MetalKit
import Observation
import SwiftUI

/// What the stage has to say to the person: why it can't draw, and how long frames
/// are taking.
@MainActor
@Observable
final class StageStatus {
    var problem: String?
    var frameTime: String?
}

/// The Metal view the visuals are drawn in.
///
/// - It draws only while its window can be seen (CLAUDE.md rule 6).
/// - It idles at a few frames a second when there's been no sound for a while.
/// - Setting up (compiling shaders, making sparks) happens away from the main thread.
///
/// It's told when to draw by a display link of its own, in step with the screen.
/// MTKView's built-in timer wasn't used: on 2026-10-03 it ran but never asked for a
/// frame when the app was opened with a song.
final class StageMetalView: MTKView, MTKViewDelegate {
    /// Frames a second with music playing, and with none.
    static let fullRate = 60
    static let idleRate = 20
    /// How long the silence has to last before it idles.
    static let idleAfterSeconds = 3.0

    var listener: MusicListener?
    var status: StageStatus?

    private var renderer: StageRenderer?
    private var settings = AcceleratorSettings()
    private var visualBeingStarted: Int?
    private var occlusionObserver: NSObjectProtocol?
    private var frameClock: CADisplayLink?
    private var currentRate = StageMetalView.fullRate
    private var lastSoundTime = CACurrentMediaTime()
    private var lastReportTime = 0.0

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // The drawable is kept at the picture's size, and the screen scales it up:
        // drawing more pixels than the quality tier allows would cost time for nothing.
        autoResizeDrawable = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Drawn only when the frame clock says so (see `tick`).
        isPaused = true
        enableSetNeedsDisplay = false
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("StageMetalView is made in code.")
    }

    // MARK: Settings

    func apply(_ newSettings: AcceleratorSettings) {
        let old = settings
        settings = newSettings
        if renderer == nil || newSettings.visual != old.visual {
            start()
        } else if newSettings.quality != old.quality {
            changeQuality()
        }
        if !newSettings.showsFrameTime { status?.frameTime = nil }
    }

    private func start() {
        guard let device else {
            status?.problem = "This Mac has no Metal graphics card, so the visuals can't run here."
            return
        }
        let number = settings.visual
        guard visualBeingStarted != number else { return }
        visualBeingStarted = number
        let tier = QualityTier.tier(for: settings.quality, isLowPowerCard: device.isLowPower)
        let format = colorPixelFormat
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try StageRenderer(device: device, visualNumber: number, tier: tier, screenFormat: format)
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finishStarting(result, visual: number) }
            }
        }
    }

    private func finishStarting(_ result: Result<StageRenderer, Error>, visual number: Int) {
        guard visualBeingStarted == number else { return }
        visualBeingStarted = nil
        switch result {
        case .success(let newRenderer):
            renderer = newRenderer
            status?.problem = nil
            changeQuality()
        case .failure(let error):
            renderer = nil
            status?.problem = error.localizedDescription
        }
    }

    private func changeQuality() {
        guard let renderer, let device else { return }
        do {
            try renderer.setTier(QualityTier.tier(for: settings.quality, isLowPowerCard: device.isLowPower))
            status?.problem = nil
        } catch {
            status?.problem = error.localizedDescription
        }
        fitPicture()
    }

    // MARK: Size

    override func layout() {
        super.layout()
        fitPicture()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        fitPicture()
    }

    private func fitPicture() {
        guard let device, bounds.width > 0, bounds.height > 0 else { return }
        let viewPixels = convertToBacking(bounds.size)
        // The drawable gets its size from the quality tier at once, so it has one even
        // before the stage is ready.
        let tier = QualityTier.tier(for: settings.quality, isLowPowerCard: device.isLowPower)
        let size = tier.pictureSize(forViewPixels: viewPixels)
        let wanted = CGSize(width: size.width, height: size.height)
        if drawableSize != wanted { drawableSize = wanted }
        do {
            try renderer?.resize(forViewPixels: viewPixels)
        } catch {
            status?.problem = error.localizedDescription
        }
    }

    // MARK: Drawing only when seen

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        frameClock?.invalidate()
        frameClock = nil
        guard let window else { return }

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseIfHidden() }
        }
        // A clock that ticks in step with whichever screen the view is on.
        let clock = displayLink(target: self, selector: #selector(tick))
        clock.preferredFrameRateRange = Self.rateRange(Self.fullRate)
        clock.add(to: .main, forMode: .common)
        frameClock = clock
        pauseIfHidden()
    }

    private func pauseIfHidden() {
        let canBeSeen = window?.occlusionState.contains(.visible) ?? false
        frameClock?.isPaused = !canBeSeen
    }

    @objc private func tick() {
        draw()
    }

    private static func rateRange(_ framesPerSecond: Int) -> CAFrameRateRange {
        let rate = Float(framesPerSecond)
        return CAFrameRateRange(minimum: min(rate, Float(idleRate)), maximum: rate, preferred: rate)
    }

    // MARK: Each frame

    func draw(in view: MTKView) {
        guard let renderer, let listener, let drawable = currentDrawable else { return }
        let now = CACurrentMediaTime()
        let reading = listener.reading()
        renderer.draw(reading: reading, at: now, into: drawable.texture, presenting: drawable)

        // With no sound for a while, a few frames a second is plenty.
        if reading.loudness > 0 { lastSoundTime = now }
        let rate = now - lastSoundTime > Self.idleAfterSeconds ? Self.idleRate : Self.fullRate
        if rate != currentRate {
            currentRate = rate
            frameClock?.preferredFrameRateRange = Self.rateRange(rate)
        }

        if settings.showsFrameTime, now - lastReportTime > 0.5 {
            lastReportTime = now
            let size = renderer.pictureSize
            status?.frameTime = "\(renderer.timer.summary.text) · \(renderer.tier.particleCount.formatted()) sparks at \(size.width)×\(size.height)"
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

/// Puts the Metal view into SwiftUI.
struct StageRepresentable: NSViewRepresentable {
    let listener: MusicListener
    let settings: AcceleratorSettings
    let status: StageStatus

    func makeNSView(context: Context) -> StageMetalView {
        let view = StageMetalView()
        view.listener = listener
        view.status = status
        view.apply(settings)
        return view
    }

    func updateNSView(_ view: StageMetalView, context: Context) {
        view.listener = listener
        view.apply(settings)
    }
}
