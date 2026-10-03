import AppKit
import SwiftUI

/// A plain view of what the listener hears, whatever it's listening to: the 64 spectrum
/// bars, the six bands (with their real loudness in decibels), the loudness and a beat
/// light. For a song file it has the play button and position, and for every source a
/// timing control.
///
/// It's for checking that the music is heard properly, before and after any visual is
/// built on it. It stops drawing when its window can't be seen.
public struct SoundCheckView: View {
    private let listener: MusicListener
    /// The bands' colours: the person's own where they've picked any, or changing by
    /// themselves if that's switched on.
    private let palette: BandPalette

    /// - Parameter controls: the person's own changes (`AcceleratorSettings.controls`),
    ///   so the bars and meters are the same colours as the visual's sections.
    public init(listener: MusicListener, controls: ControlValues = ControlValues()) {
        self.listener = listener
        palette = BandPalette(controls)
    }

    public var body: some View {
        // Drawn again only when the listener or a colour changes. Without this it was
        // laid out afresh for every step of a slider being dragged, though no slider
        // changes anything in it (measured 2026-10-03).
        SoundCheckContent(listener: listener, palette: palette)
            .equatable()
    }
}

/// The sound check itself.
private struct SoundCheckContent: View, Equatable {
    let listener: MusicListener
    let palette: BandPalette
    @State private var meters = SoundCheckMeters()
    @State private var isWindowVisible: Bool = true
    /// Where the position slider is being dragged to, while it's being dragged.
    @State private var draggedTime: Double?
    @State private var problem: String?

    static func == (one: SoundCheckContent, other: SoundCheckContent) -> Bool {
        one.listener === other.listener && one.palette == other.palette
    }

    var body: some View {
        // With a song file paused, a few frames a second is plenty to let the bars settle.
        let isLive = listener.isPlaying || (listener.source != .songFile && listener.source != .nothing)
        VStack(alignment: .leading, spacing: 16) {
            header
            ZStack(alignment: .bottomLeading) {
                // Everything that moves with the music is plain shapes, drawn in one
                // pass for each frame, and nothing else is touched. Laying the whole
                // view out afresh for every frame, words and all, took a whole
                // processor core, and the visual beside it dropped to 45 frames a
                // second (measured 2026-10-03).
                TimelineView(
                    .animation(
                        minimumInterval: isLive ? nil : 1.0 / 20,
                        paused: !isWindowVisible || listener.source == .nothing)
                ) { timeline in
                    // The colours at this moment, by the same clock the stage uses.
                    LiveMeters(
                        display: meters.update(listener.reading(), at: timeline.date),
                        colours: palette.colours(at: CACurrentMediaTime()).map {
                            Color(.sRGB, red: Double($0.x), green: Double($0.y), blue: Double($0.z))
                        })
                }
                // The words under the meters. Only the decibels and the tempo change,
                // and a few times a second is plenty for those.
                TimelineView(.animation(minimumInterval: 0.25, paused: !isWindowVisible)) { _ in
                    MeterWords(reading: meters.reading, isPlaying: listener.isPlaying)
                }
            }
            .frame(minHeight: 230)
            // The same goes for the position, the clock and any hint.
            TimelineView(.animation(minimumInterval: 0.25, paused: !isWindowVisible)) { _ in
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    if let note = listener.problem ?? problem ?? hint(silentSeconds: meters.silentSeconds) {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .background(WindowVisibility(isVisible: $isWindowVisible))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Text("Sound check")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch listener.source {
        case .nothing: return "Nothing playing"
        case .player: return listener.sourceName ?? "A player"
        default: return listener.sourceName ?? ""
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch listener.source {
            case .songFile, .nothing:
                songControls
            case .thisMac:
                Label("Listening to everything this Mac plays", systemImage: "desktopcomputer")
                Spacer()
            case .microphone:
                Label("Listening to the microphone", systemImage: "mic.fill")
                Spacer()
            case .player:
                Label("Listening to an app's player", systemImage: "play.rectangle.fill")
                Spacer()
            }
            timingControl
        }
    }

    @ViewBuilder private var songControls: some View {
        let hasSong = listener.songTitle != nil
        let time = draggedTime ?? listener.currentTime
        Button {
            playOrPause()
        } label: {
            Image(systemName: listener.isPlaying ? "pause.fill" : "play.fill")
                .frame(width: 18, height: 18)
        }
        .help(listener.isPlaying ? "Pause" : "Play")
        .disabled(!hasSong)

        Button {
            listener.isMuted.toggle()
        } label: {
            Image(systemName: listener.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 18, height: 18)
        }
        .help(listener.isMuted ? "Turn the sound back on" : "Mute: the bars still move")
        .accessibilityLabel(listener.isMuted ? "Unmute" : "Mute")

        Text(SoundCheckView.clock(time))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        Slider(
            value: Binding(get: { time }, set: { draggedTime = $0 }),
            in: 0...max(listener.duration, 0.1)
        ) { isDragging in
            if !isDragging, let draggedTime {
                listener.seek(to: draggedTime)
                self.draggedTime = nil
            }
        }
        .disabled(!hasSong)
        Text(SoundCheckView.clock(listener.duration))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// Shows the bars a little later or earlier, in steps of a hundredth of a second.
    private var timingControl: some View {
        let thousandths = Binding(
            get: { (listener.timingOffset * 1_000).rounded() },
            set: { listener.timingOffset = $0 / 1_000 })
        return Stepper(value: thousandths, in: -500...500, step: 10) {
            Text("Timing \(SoundCheckView.signed(Int(thousandths.wrappedValue))) ms")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help("Show the picture later (+) or earlier (−) than the sound, if they don't line up")
        .fixedSize()
    }

    /// Nothing at all has been heard from the Mac for a while: say what may be wrong.
    private func hint(silentSeconds: Double) -> String? {
        guard listener.source == .thisMac, silentSeconds > 4 else { return nil }
        return "Nothing heard yet. If something is playing, allow Particle Accelerator in System Settings → Privacy & Security → Screen & System Audio Recording, then choose This Mac's Sound again."
    }

    private func playOrPause() {
        problem = nil
        if listener.isPlaying {
            listener.pause()
        } else {
            do {
                try listener.resume()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

}

// MARK: - Words

extension SoundCheckView {
    /// 20 as "+20", -30 as "−30" and 0 as "0".
    static func signed(_ number: Int) -> String {
        number > 0 ? "+\(number)" : number < 0 ? "−\(-number)" : "0"
    }

    /// A loudness in decibels as "−23 dB", or a dash for silence.
    static func decibelsText(_ decibels: Float) -> String {
        decibels <= SoundReading.silenceDecibels + 1 ? "–" : "\(signed(Int(decibels.rounded()))) dB"
    }

    /// 83 seconds as "1:23".
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds.isFinite ? seconds : 0))
        let secondsPart = whole % 60
        return "\(whole / 60):\(secondsPart < 10 ? "0" : "")\(secondsPart)"
    }

    /// A band's pitches as "60–150 Hz" or "2–6 kHz".
    static func pitches(of band: Band) -> String {
        let low = band.frequencies.lowerBound
        let high = band.frequencies.upperBound
        if low >= 1_000 {
            return "\(Int(low / 1_000))–\(Int(high / 1_000)) kHz"
        }
        if high >= 1_000 {
            return "\(Int(low)) Hz–\(Int(high / 1_000)) kHz"
        }
        return "\(Int(low))–\(Int(high)) Hz"
    }
}

// MARK: - The parts

/// The sound check's own smoothing, so the bars and meters are easy to read. It runs the
/// same signal chains the visuals will.
private final class SoundCheckMeters {
    struct Display {
        var reading = SoundReading.silence
        var bars = SIMD64<Float>(repeating: 0)
        var bands = BandValues()
        var loudness: Float = 0
        var beat: Float = 0
        /// How long it's been since anything at all was heard.
        var silentSeconds: Double = 0
    }

    private static let quick = SignalShape(riseSeconds: 0.01, fallSeconds: 0.15)
    private var spectrum = LiveSpectrum(quick)
    private var bands = Band.allCases.map { LiveSignal(SignalChain(source: $0.source, shape: quick)) }
    private var loudness = LiveSignal(SignalChain(source: .loudness, shape: quick))
    private var beat = LiveSignal(
        SignalChain(source: .beat, shape: SignalShape(riseSeconds: 0, fallSeconds: 0.2)))
    private var display = Display()
    private var lastFrame: Date?

    /// How long it's been since anything at all was heard.
    var silentSeconds: Double { display.silentSeconds }
    /// What was last heard.
    var reading: SoundReading { display.reading }

    func update(_ reading: SoundReading, at date: Date) -> Display {
        // A long gap (the window was hidden) counts as one short frame.
        let seconds = min(0.1, max(0, lastFrame.map { date.timeIntervalSince($0) } ?? 0))
        lastFrame = date
        display.reading = reading
        display.bars = spectrum.update(reading, seconds: seconds)
        for band in Band.allCases {
            display.bands[band] = bands[band.rawValue].update(reading, seconds: seconds)
        }
        display.loudness = loudness.update(reading, seconds: seconds)
        display.beat = beat.update(reading, seconds: seconds)
        let isSilent = reading.loudnessDecibels <= SoundReading.silenceDecibels + 1
        display.silentSeconds = isSilent ? display.silentSeconds + seconds : 0
        return display
    }
}

/// Where things sit in the row of meters, shared by the shapes and the words under them.
private enum MeterRow {
    /// The whole row's height, and how much of it at the bottom is words.
    static let height: CGFloat = 150
    static let wordsHeight: CGFloat = 52
    /// Each meter has a column this wide: room for "Vocals and snare".
    static let columnWidth: CGFloat = 88
    static let columnGap: CGFloat = 2
    /// The beat light's column, at the right.
    static let beatWidth: CGFloat = 150
}

/// Everything in the sound check that moves with the music, as plain shapes drawn in one
/// pass: the 64 bars, the six bands' meters and the loudness, and the beat light with
/// four dots that step once a beat. The words are in `MeterWords`.
private struct LiveMeters: View {
    let display: SoundCheckMeters.Display
    /// Each band's colour, sub first.
    let colours: [Color]

    /// The band each bar of the spectrum belongs to.
    private static let bandOfBar = (0..<SoundAnalyser.barCount).map { Band.of(bar: $0).rawValue }

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let barsHeight = max(40, size.height - MeterRow.height - 16)
            drawBars(&context, in: CGRect(x: 0, y: 0, width: size.width, height: barsHeight))
            let row = CGRect(x: 0, y: size.height - MeterRow.height, width: size.width, height: MeterRow.height)
            drawMeters(&context, in: row)
            drawBeat(
                &context,
                in: CGRect(x: row.maxX - MeterRow.beatWidth, y: row.minY, width: MeterRow.beatWidth, height: row.height))
        }
        .accessibilityLabel("Spectrum and levels: bass on the left, highs on the right")
    }

    /// The spectrum: bass on the left, highs on the right, each bar in its band's colour.
    private func drawBars(_ context: inout GraphicsContext, in area: CGRect) {
        let count = SoundAnalyser.barCount
        let gap: CGFloat = 2
        let width = max(1, (area.width - gap * CGFloat(count - 1)) / CGFloat(count))
        for index in 0..<count {
            let height = max(2, CGFloat(display.bars[index]) * area.height)
            let bar = CGRect(
                x: area.minX + CGFloat(index) * (width + gap), y: area.maxY - height, width: width,
                height: height)
            context.fill(
                Path(roundedRect: bar, cornerRadius: min(2, width / 2)),
                with: .color(colours[Self.bandOfBar[index]]))
        }
    }

    /// The six bands' meters and the loudness, one above each column of words.
    private func drawMeters(_ context: inout GraphicsContext, in row: CGRect) {
        var meters = Band.allCases.map { (level: display.bands[$0], colour: colours[$0.rawValue]) }
        meters.append((display.loudness, .white))
        for (column, meter) in meters.enumerated() {
            let middle = row.minX + CGFloat(column) * (MeterRow.columnWidth + MeterRow.columnGap)
                + MeterRow.columnWidth / 2
            let track = CGRect(
                x: middle - 13, y: row.minY, width: 26, height: row.height - MeterRow.wordsHeight)
            context.fill(Path(roundedRect: track, cornerRadius: 4), with: .color(.white.opacity(0.08)))
            let height = max(2, track.height * CGFloat(meter.level))
            let filled = CGRect(x: track.minX, y: track.maxY - height, width: track.width, height: height)
            context.fill(Path(roundedRect: filled, cornerRadius: 4), with: .color(meter.colour))
        }
    }

    /// A light that pulses on each beat heard, and four dots that step once a beat on
    /// the steady count.
    private func drawBeat(_ context: inout GraphicsContext, in area: CGRect) {
        let pulse = Double(display.beat)
        let middle = CGPoint(x: area.midX, y: area.minY + 38)
        let orange = Color(hue: 0.06, saturation: 0.7, brightness: 1)
        // A soft glow around the light, then the light itself.
        let glow = CGRect(x: middle.x - 44, y: middle.y - 44, width: 88, height: 88)
        context.fill(
            Path(ellipseIn: glow),
            with: .radialGradient(
                Gradient(colors: [Color.orange.opacity(0.55 * pulse), Color.orange.opacity(0)]),
                center: middle, startRadius: 24, endRadius: 44))
        let light = CGRect(x: middle.x - 27, y: middle.y - 27, width: 54, height: 54)
        context.fill(Path(ellipseIn: light), with: .color(.black))
        context.fill(Path(ellipseIn: light), with: .color(orange.opacity(0.12 + 0.88 * pulse)))

        let hasTempo = display.reading.beatsPerMinute != nil
        for step in 0..<4 {
            let dot = CGRect(x: middle.x - 25 + CGFloat(step) * 14, y: middle.y + 50, width: 8, height: 8)
            let isNow = hasTempo && display.reading.steadyBeats % 4 == step
            context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(isNow ? 0.9 : 0.15)))
        }
    }
}

/// The words under the meters: each band's name, its pitches and its real loudness in
/// decibels, and the tempo under the beat light.
private struct MeterWords: View {
    let reading: SoundReading
    let isPlaying: Bool

    private var tempo: String {
        if let beatsPerMinute = reading.beatsPerMinute { return "\(Int(beatsPerMinute.rounded())) BPM" }
        return isPlaying ? "Finding the tempo…" : "– BPM"
    }

    var body: some View {
        HStack(alignment: .top, spacing: MeterRow.columnGap) {
            ForEach(Band.allCases, id: \.self) { band in
                words(band.name, SoundCheckView.pitches(of: band), decibels: reading.bandDecibels[band])
            }
            words("Loudness", "everything", decibels: reading.loudnessDecibels)
            Spacer(minLength: 0)
            Text(tempo)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(width: MeterRow.beatWidth)
                .accessibilityLabel("Beat")
                .accessibilityValue(
                    reading.beatsPerMinute.map { "\(Int($0.rounded())) beats a minute" } ?? "Finding the tempo")
        }
        .lineLimit(1)
        .padding(.top, 6)
        .frame(height: MeterRow.wordsHeight, alignment: .top)
    }

    private func words(_ name: String, _ detail: String, decibels: Float) -> some View {
        VStack(spacing: 3) {
            Text(name)
                .font(.caption.weight(.medium))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(SoundCheckView.decibelsText(decibels))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .frame(width: MeterRow.columnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(detail)")
        .accessibilityValue(SoundCheckView.decibelsText(decibels))
    }
}

/// Tells the view whether its window can be seen at all, so drawing can stop when it's
/// minimised or covered (CLAUDE.md rule 6).
private struct WindowVisibility: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> WatchingView {
        let view = WatchingView()
        view.onChange = { [binding = $isVisible] visible in
            // Not straight away: this can arrive while SwiftUI is laying the view out.
            DispatchQueue.main.async {
                if binding.wrappedValue != visible { binding.wrappedValue = visible }
            }
        }
        return view
    }

    func updateNSView(_ view: WatchingView, context: Context) {}

    final class WatchingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else {
                onChange?(false)
                return
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            onChange?(window?.occlusionState.contains(.visible) ?? false)
        }
    }
}
