import AppKit
import Metal
import Observation
import QuartzCore
import SwiftUI

/// What the stage has to say to the person: why it can't draw, and how long frames
/// are taking.
@MainActor
@Observable
final class StageStatus {
    var problem: String?
    var frameTime: String?
}

/// How often the stage draws: every frame while there's music, and a few frames a
/// second once it has been silent for a while.
struct FramePacing {
    /// Frames a second with music playing, and with none.
    static let fullRate = 60
    static let idleRate = 20
    /// How long the silence has to last before it idles.
    static let idleAfterSeconds = 3.0

    private var lastSoundTime: Double?

    /// The frames a second to draw at.
    /// - Parameters:
    ///   - now: seconds on any steady clock.
    ///   - loudness: how loud the music is in this frame, from 0.
    mutating func rate(at now: Double, loudness: Float) -> Int {
        if loudness > 0 || lastSoundTime == nil { lastSoundTime = now }
        return now - (lastSoundTime ?? now) > Self.idleAfterSeconds ? Self.idleRate : Self.fullRate
    }

    static func rateRange(_ framesPerSecond: Int) -> CAFrameRateRange {
        let rate = Float(framesPerSecond)
        return CAFrameRateRange(minimum: min(rate, Float(idleRate)), maximum: rate, preferred: rate)
    }
}

/// A thread of the stage's own, so that drawing never waits for the main thread
/// (CLAUDE.md rule 6).
///
/// Measured on 2026-10-03, with the stage drawing on the main thread: when the rest of
/// the window was busy (the sound check laying itself out, every slider redrawn), the
/// visual fell from 60 frames a second to 45, though the graphics card had time to
/// spare.
///
/// The thread waits in a run loop. The screen's frame clock wakes it for each frame,
/// and `perform` hands it anything else to do, in the order it was handed over.
final class StageThread: @unchecked Sendable {
    private let runLoop: CFRunLoop
    private let thread: Thread

    init(name: String) {
        final class Found: @unchecked Sendable { var runLoop: CFRunLoop? }
        let found = Found()
        let started = DispatchSemaphore(value: 0)
        thread = Thread {
            // A run loop with nothing to wait for ends at once. This gives it something.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            found.runLoop = CFRunLoopGetCurrent()
            started.signal()
            while !Thread.current.isCancelled {
                // Each turn of the loop is one frame or one piece of work. Whatever it
                // made and let go of (a frame's drawable) is cleared away after it.
                autoreleasepool {
                    _ = RunLoop.current.run(mode: .default, before: .distantFuture)
                }
            }
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        runLoop = found.runLoop!
    }

    /// Runs this on the stage's thread, after anything handed over before it.
    func perform(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    /// Ends the thread, once it has done everything already handed to it.
    func stop() {
        perform {
            Thread.current.cancel()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    /// Whether the thread has ended, after `stop`.
    var hasEnded: Bool { thread.isFinished }
}

/// Draws the stage's frames. Everything here happens on the stage's own thread: the
/// view hands each call over with `StageThread.perform`, and the frame clock calls
/// `tick` there.
final class StageDrawer: NSObject {
    /// Called with a plain-English problem, or nil when it's gone. On the stage's
    /// thread: the receiver hops to the main thread.
    var onProblem: ((String?) -> Void)?
    /// Called twice a second with the frame-time line, while it's wanted.
    var onFrameTime: ((String) -> Void)?

    private let layer: CAMetalLayer
    private var renderer: StageRenderer?
    private var readings: Readings?
    private var clock: CADisplayLink?
    private var pacing = FramePacing()
    private var currentRate = FramePacing.fullRate
    private var showsFrameTime = false
    private var lastReportTime = 0.0

    init(layer: CAMetalLayer) {
        self.layer = layer
    }

    // MARK: What to draw

    func listen(to readings: Readings?) {
        self.readings = readings
    }

    /// Takes over a stage that's ready to draw.
    func use(_ renderer: StageRenderer, values: ControlValues, viewPixels: CGSize) {
        self.renderer = renderer
        renderer.values = values
        resize(forViewPixels: viewPixels)
    }

    /// Lets go of the stage, when it couldn't be set up.
    func useNothing() {
        renderer = nil
    }

    func setValues(_ values: ControlValues) {
        renderer?.values = values
    }

    func setTier(_ tier: QualityTier, viewPixels: CGSize) {
        guard let renderer else { return }
        do {
            try renderer.setTier(tier)
            onProblem?(nil)
        } catch {
            onProblem?(error.localizedDescription)
        }
        resize(forViewPixels: viewPixels)
    }

    func resize(forViewPixels viewPixels: CGSize) {
        guard let renderer, viewPixels.width > 0, viewPixels.height > 0 else { return }
        do {
            try renderer.resize(forViewPixels: viewPixels)
        } catch {
            onProblem?(error.localizedDescription)
        }
    }

    func showFrameTime(_ shows: Bool) {
        showsFrameTime = shows
    }

    // MARK: When to draw

    /// Starts drawing in step with this frame clock, which the view made for the
    /// screen it's on.
    func start(_ newClock: CADisplayLink, paused: Bool) {
        clock?.invalidate()
        clock = newClock
        currentRate = FramePacing.fullRate
        newClock.preferredFrameRateRange = FramePacing.rateRange(currentRate)
        newClock.isPaused = paused
        newClock.add(to: .current, forMode: .default)
    }

    /// Stops drawing while the window can't be seen (CLAUDE.md rule 6).
    func setPaused(_ paused: Bool) {
        clock?.isPaused = paused
    }

    /// Stops for good. The frame clock holds on to this drawer until it's told to stop.
    func stop() {
        clock?.invalidate()
        clock = nil
    }

    // MARK: Each frame

    @objc func tick(_ clock: CADisplayLink) {
        guard let renderer, let readings, let drawable = layer.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        let reading = readings.reading()
        renderer.draw(reading: reading, at: now, into: drawable.texture, presenting: drawable)

        // With no sound for a while, a few frames a second is plenty.
        let rate = pacing.rate(at: now, loudness: reading.loudness)
        if rate != currentRate {
            currentRate = rate
            clock.preferredFrameRateRange = FramePacing.rateRange(rate)
        }

        if showsFrameTime, now - lastReportTime > 0.5 {
            lastReportTime = now
            let size = renderer.pictureSize
            onFrameTime?(
                "\(renderer.timer.summary.text) · \(renderer.tier.particleCount.formatted()) sparks at \(size.width)×\(size.height)")
        }
    }
}

/// The view the visuals are drawn in.
///
/// - Frames are drawn on a thread of the stage's own (`StageThread`), in step with the
///   screen, so nothing else the window is doing can hold them up.
/// - It draws only while its window can be seen (CLAUDE.md rule 6).
/// - It idles at a few frames a second when there's been no sound for a while.
/// - Setting up (compiling shaders, making sparks) happens away from both threads.
///
/// The view itself stays on the main thread, like every view. It keeps the settings,
/// follows the window, and hands the stage's thread whatever changes.
final class StageMetalView: NSView {
    var listener: MusicListener? {
        didSet {
            guard listener !== oldValue else { return }
            let readings = listener?.readings
            stage.perform { [drawer] in drawer.listen(to: readings) }
        }
    }
    var status: StageStatus?

    private let device = MTLCreateSystemDefaultDevice()
    private let metalLayer = CAMetalLayer()
    private let stage = StageThread(name: "Particle Accelerator stage")
    private let drawer: StageDrawer
    private var settings = AcceleratorSettings()
    /// The visual the stage is set up for, the one being set up, and the one that
    /// couldn't be (so it isn't tried again for every change to the settings).
    private var visualShowing: Int?
    private var visualBeingStarted: Int?
    private var visualThatCouldNotStart: Int?
    private var occlusionObserver: NSObjectProtocol?

    init() {
        drawer = StageDrawer(layer: metalLayer)
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        wantsLayer = true

        drawer.onProblem = { [weak self] problem in
            DispatchQueue.main.async { self?.status?.problem = problem }
        }
        drawer.onFrameTime = { [weak self] text in
            DispatchQueue.main.async {
                guard let self, self.settings.showsFrameTime else { return }
                self.status?.frameTime = text
            }
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("StageMetalView is made in code.")
    }

    deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        stage.perform { [drawer] in drawer.stop() }
        stage.stop()
    }

    /// The view's layer is the one Metal draws into.
    override func makeBackingLayer() -> CALayer {
        metalLayer
    }

    // MARK: Settings

    func apply(_ newSettings: AcceleratorSettings) {
        let old = settings
        settings = newSettings
        if newSettings.quality != old.quality {
            // A lower quality may fit where the last one didn't.
            visualThatCouldNotStart = nil
        }
        if newSettings.visual != visualShowing {
            if newSettings.visual != visualThatCouldNotStart { start() }
        } else if newSettings.quality != old.quality {
            changeQuality()
        }
        if newSettings.controls != old.controls {
            let values = newSettings.controls
            stage.perform { [drawer] in drawer.setValues(values) }
        }
        if newSettings.showsFrameTime != old.showsFrameTime {
            let shows = newSettings.showsFrameTime
            stage.perform { [drawer] in drawer.showFrameTime(shows) }
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
        let format = metalLayer.pixelFormat
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
        case .success(let renderer):
            visualShowing = number
            visualThatCouldNotStart = nil
            status?.problem = nil
            let values = settings.controls
            let shows = settings.showsFrameTime
            let viewPixels = convertToBacking(bounds.size)
            stage.perform { [drawer] in
                drawer.use(renderer, values: values, viewPixels: viewPixels)
                drawer.showFrameTime(shows)
            }
            // The quality may have been changed while the stage was being set up.
            changeQuality()
        case .failure(let error):
            visualShowing = nil
            visualThatCouldNotStart = number
            stage.perform { [drawer] in drawer.useNothing() }
            status?.problem = error.localizedDescription
        }
    }

    private func changeQuality() {
        guard let device, visualShowing != nil else { return }
        let tier = QualityTier.tier(for: settings.quality, isLowPowerCard: device.isLowPower)
        let viewPixels = convertToBacking(bounds.size)
        stage.perform { [drawer] in drawer.setTier(tier, viewPixels: viewPixels) }
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

    /// The frames are drawn at the picture's size, which the quality tier sets, and the
    /// screen scales them up: drawing more pixels than the tier allows would cost time
    /// for nothing.
    private func fitPicture() {
        guard let device, bounds.width > 0, bounds.height > 0 else { return }
        let viewPixels = convertToBacking(bounds.size)
        let tier = QualityTier.tier(for: settings.quality, isLowPowerCard: device.isLowPower)
        let size = tier.pictureSize(forViewPixels: viewPixels)
        let wanted = CGSize(width: size.width, height: size.height)
        if metalLayer.drawableSize != wanted { metalLayer.drawableSize = wanted }
        stage.perform { [drawer] in drawer.resize(forViewPixels: viewPixels) }
    }

    // MARK: Drawing only when seen

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        guard let window else {
            stage.perform { [drawer] in drawer.stop() }
            return
        }

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseIfHidden() }
        }
        // A clock that ticks in step with whichever screen the view is on. It's made
        // here, and then runs on the stage's thread.
        let clock = displayLink(target: drawer, selector: #selector(StageDrawer.tick(_:)))
        let canBeSeen = window.occlusionState.contains(.visible)
        stage.perform { [drawer] in drawer.start(clock, paused: !canBeSeen) }
    }

    private func pauseIfHidden() {
        let canBeSeen = window?.occlusionState.contains(.visible) ?? false
        stage.perform { [drawer] in drawer.setPaused(!canBeSeen) }
    }
}

/// Puts the stage's view into SwiftUI.
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
