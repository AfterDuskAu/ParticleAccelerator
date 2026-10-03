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
    @State private var meters = SoundCheckMeters()
    @State private var isWindowVisible: Bool = true
    /// Where the position slider is being dragged to, while it's being dragged.
    @State private var draggedTime: Double?
    @State private var problem: String?

    public init(listener: MusicListener) {
        self.listener = listener
    }

    public var body: some View {
        // With a song file paused, a few frames a second is plenty to let the bars settle.
        let isLive = listener.isPlaying || (listener.source != .songFile && listener.source != .nothing)
        TimelineView(
            .animation(
                minimumInterval: isLive ? nil : 1.0 / 20,
                paused: !isWindowVisible || listener.source == .nothing)
        ) { timeline in
            let display = meters.update(listener.reading(), at: timeline.date)
            VStack(alignment: .leading, spacing: 20) {
                header
                SpectrumBars(bars: display.bars)
                    .frame(minHeight: 140)
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(Band.allCases, id: \.self) { band in
                        LevelMeter(
                            level: display.bands[band], name: band.name,
                            detail: Self.pitches(of: band),
                            decibels: display.reading.bandDecibels[band], colour: Self.colour(of: band))
                    }
                    LevelMeter(
                        level: display.loudness, name: "Loudness", detail: "everything",
                        decibels: display.reading.loudnessDecibels, colour: .white)
                    Spacer(minLength: 12)
                    BeatLight(
                        pulse: display.beat, beatsPerMinute: display.reading.beatsPerMinute,
                        steadyBeats: display.reading.steadyBeats, isPlaying: listener.isPlaying)
                }
                .frame(height: 165)
                controls
                if let note = listener.problem ?? problem ?? hint(silentSeconds: display.silentSeconds) {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
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

        Text(Self.clock(time))
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
        Text(Self.clock(listener.duration))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// Shows the bars a little later or earlier, in steps of a hundredth of a second.
    private var timingControl: some View {
        let thousandths = Binding(
            get: { (listener.timingOffset * 1_000).rounded() },
            set: { listener.timingOffset = $0 / 1_000 })
        return Stepper(value: thousandths, in: -500...500, step: 10) {
            Text("Timing \(Self.signed(Int(thousandths.wrappedValue))) ms")
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

    // MARK: Words and colours

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

    /// The band's own colour, the same one its section of Visualizer 3 has.
    static func colour(of band: Band) -> Color {
        let colour = band.colour
        return Color(red: Double(colour.x), green: Double(colour.y), blue: Double(colour.z))
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

private struct SpectrumBars: View {
    let bars: SIMD64<Float>

    var body: some View {
        Canvas { context, size in
            let count = SoundAnalyser.barCount
            let gap: CGFloat = 2
            let width = max(1, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            for index in 0..<count {
                let height = max(2, CGFloat(bars[index]) * size.height)
                let bar = CGRect(
                    x: CGFloat(index) * (width + gap), y: size.height - height, width: width,
                    height: height)
                let colour = SoundCheckView.colour(of: Band.of(bar: index))
                context.fill(Path(roundedRect: bar, cornerRadius: min(2, width / 2)), with: .color(colour))
            }
        }
        .accessibilityLabel("Spectrum: bass on the left, highs on the right")
    }
}

private struct LevelMeter: View {
    let level: Float
    let name: String
    let detail: String
    /// The real loudness, before auto-gain.
    let decibels: Float
    let colour: Color

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { space in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4).fill(colour)
                        .frame(height: max(2, space.size.height * CGFloat(level)))
                }
            }
            .frame(width: 26)
            Text(name)
                .font(.caption.weight(.medium))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(SoundCheckView.decibelsText(decibels))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(minWidth: 44)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(detail)")
        .accessibilityValue("\(Int((level * 100).rounded())) percent, \(SoundCheckView.decibelsText(decibels))")
    }
}

/// A small light that pulses on each beat heard, the tempo, and four dots that step
/// once a beat on the steady count.
private struct BeatLight: View {
    let pulse: Float
    let beatsPerMinute: Double?
    let steadyBeats: Int
    let isPlaying: Bool

    private var tempo: String {
        if let beatsPerMinute { return "\(Int(beatsPerMinute.rounded())) BPM" }
        return isPlaying ? "Finding the tempo…" : "– BPM"
    }

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color(hue: 0.06, saturation: 0.7, brightness: 1).opacity(0.12 + 0.88 * Double(pulse)))
                .frame(width: 54, height: 54)
                .shadow(color: .orange.opacity(0.8 * Double(pulse)), radius: 14)
            Text(tempo)
                .font(.callout.weight(.medium))
                .monospacedDigit()
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { step in
                    Circle()
                        .fill(Color.white.opacity(beatsPerMinute != nil && steadyBeats % 4 == step ? 0.9 : 0.15))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beat")
        .accessibilityValue(beatsPerMinute.map { "\(Int($0.rounded())) beats a minute" } ?? "Finding the tempo")
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
