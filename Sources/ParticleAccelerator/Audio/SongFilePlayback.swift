import AVFoundation
import AudioToolbox

/// Something that stopped the music being heard, said so a person can act on it.
struct ListeningProblem: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Plays one song file through the Mac's speakers, and copies exactly what is played
/// into a `SampleRing` for the analyser.
///
/// The sound goes player → pass-through → mixer → speakers. The copy is taken at the
/// pass-through by a Core Audio "render notify": it runs on the audio thread about 86
/// times a second with the song's own samples, before the mixer's volume. So muting
/// silences the speakers and the analyser still hears the song.
///
/// Measured on 2026-10-03: what's copied matches the file sample for sample, and
/// AVAudioEngine's own tap only delivers every tenth of a second, far too jerky to draw
/// from.
///
/// Use it from the main thread only.
final class SongFilePlayback {
    let title: String
    let duration: TimeInterval
    private(set) var isPlaying = false
    /// The sound being played, for the analyser.
    let ring: SampleRing
    /// Whether the speakers are silenced. The analyser hears the song either way.
    var isMuted = false {
        didSet { applyMute() }
    }
    /// Called when playing stops without being asked to: the song ended, or the Mac's
    /// sound output went away.
    var onStopped: (() -> Void)?

    private let file: AVAudioFile
    private let fileRate: Double
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// An equaliser switched off ("bypassed"), so it passes the sound through untouched.
    /// It's here because it's a point in the chain where Core Audio lets the sound be
    /// copied.
    private let passThrough = AVAudioUnitEQ(numberOfBands: 1)
    private var isConnected = false
    private var isCopying = false
    /// Where in the file the part now scheduled on the player begins.
    private var startFrame: AVAudioFramePosition = 0
    private var isScheduled = false
    /// Goes up whenever what's scheduled changes, so a finished-playing message from an
    /// earlier schedule is ignored.
    private var schedule = 0
    /// The position when playing last began or stopped, and when it began by the Mac's
    /// clock (seconds since it started up).
    private var heldTime: TimeInterval = 0
    private var playBeganAt: TimeInterval = 0
    private var engineRest: DispatchWorkItem?
    private var outputChangeObserver: NSObjectProtocol?

    init(url: URL) throws {
        let name = url.lastPathComponent
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw ListeningProblem(
                message: "“\(name)” can't be played. It may not be a sound file, or it's in a format macOS can't read.")
        }
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            throw ListeningProblem(message: "“\(name)” has no sound in it.")
        }
        fileRate = file.processingFormat.sampleRate
        title = url.deletingPathExtension().lastPathComponent
        duration = Double(file.length) / fileRate
        ring = SampleRing(sampleRate: fileRate)
        passThrough.bypass = true
    }

    deinit {
        shutDown()
    }

    /// Where the song is, in seconds.
    var currentTime: TimeInterval {
        guard isPlaying else { return heldTime }
        guard let rendered = player.lastRenderTime, rendered.isSampleTimeValid,
            let played = player.playerTime(forNodeTime: rendered)
        else {
            // The engine can't say (it has just started, or the output has just
            // changed): work it out from the clock.
            let sincePlayBegan = ProcessInfo.processInfo.systemUptime - playBeganAt
            return min(duration, heldTime + sincePlayBegan)
        }
        let time = Double(startFrame) / fileRate + Double(played.sampleTime) / played.sampleRate
        return min(duration, max(0, time))
    }

    func play() throws {
        engineRest?.cancel()
        try connectIfNeeded()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                throw ListeningProblem(
                    message: "The Mac's sound output couldn't start. Check that speakers or headphones are chosen in System Settings → Sound.")
            }
        }
        if !isScheduled {
            scheduleFile(from: startFrame)
        }
        player.play()
        playBeganAt = ProcessInfo.processInfo.systemUptime
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        heldTime = currentTime
        player.pause()
        isPlaying = false
        restEngineSoon()
    }

    func seek(to seconds: TimeInterval) {
        let frame = AVAudioFramePosition((min(duration, max(0, seconds)) * fileRate).rounded())
        schedule += 1
        player.stop()
        isScheduled = false
        startFrame = min(frame, file.length - 1)
        heldTime = Double(startFrame) / fileRate
        playBeganAt = ProcessInfo.processInfo.systemUptime
        if isPlaying {
            scheduleFile(from: startFrame)
            player.play()
        }
    }

    /// Stops for good and lets go of the Mac's sound output.
    func shutDown() {
        engineRest?.cancel()
        schedule += 1
        isPlaying = false
        if isConnected {
            player.stop()
            engine.stop()
            stopCopying()
        }
        if let outputChangeObserver {
            NotificationCenter.default.removeObserver(outputChangeObserver)
        }
        outputChangeObserver = nil
    }

    // MARK: Setting up

    /// Joins the player to the Mac's output. Left until the first play so that opening a
    /// file never needs the sound output.
    private func connectIfNeeded() throws {
        if !isConnected {
            guard engine.outputNode.inputFormat(forBus: 0).sampleRate > 0 else {
                throw ListeningProblem(
                    message: "This Mac has no sound output to play through. Check System Settings → Sound.")
            }
            engine.attach(player)
            engine.attach(passThrough)
            engine.connect(player, to: passThrough, format: file.processingFormat)
            engine.connect(passThrough, to: engine.mainMixerNode, format: file.processingFormat)
            isConnected = true
            applyMute()

            outputChangeObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                self?.outputChanged()
            }
        }
        if !isCopying {
            try startCopying()
            isCopying = true
        }
    }

    private func scheduleFile(from frame: AVAudioFramePosition) {
        schedule += 1
        let thisSchedule = schedule
        let framesLeft = AVAudioFrameCount(max(1, file.length - frame))
        player.scheduleSegment(
            file, startingFrame: frame, frameCount: framesLeft, at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            // This arrives on one of AVFoundation's own threads.
            DispatchQueue.main.async { self?.finishedPlaying(schedule: thisSchedule) }
        }
        startFrame = frame
        isScheduled = true
    }

    private func finishedPlaying(schedule finished: Int) {
        guard finished == schedule, isPlaying else { return }
        // The song has played to its end: go back to the start, ready to play again.
        schedule += 1
        player.stop()
        isScheduled = false
        isPlaying = false
        startFrame = 0
        heldTime = 0
        restEngineSoon()
        onStopped?()
    }

    /// Stops the Mac's sound output a moment after the music stops, so the Mac can sleep.
    /// The moment lets the analyser hear the silence, and the bars fall to nothing.
    private func restEngineSoon() {
        engineRest?.cancel()
        let rest = DispatchWorkItem { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.engine.pause()
        }
        engineRest = rest
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: rest)
    }

    /// The Mac's sound output changed (headphones plugged in, say), and the engine has
    /// stopped itself. Carry on from the same place on the new output.
    private func outputChanged() {
        let wasPlaying = isPlaying
        let time = currentTime
        isPlaying = false
        seek(to: time)

        applyMute()
        guard wasPlaying else { return }
        do {
            try play()
        } catch {
            onStopped?()
        }
    }

    private func applyMute() {
        // Before the first play there's no mixer yet; connectIfNeeded calls this again.
        guard isConnected else { return }
        engine.mainMixerNode.outputVolume = isMuted ? 0 : 1
    }

    // MARK: Copying what's played

    private func startCopying() throws {
        guard passThrough.outputFormat(forBus: 0).commonFormat == .pcmFormatFloat32 else {
            throw ListeningProblem(
                message: "“\(title)” can't be listened to (its sound isn't in the usual format).")
        }
        // Core Audio is given a plain pointer to the ring. `self.ring` keeps the ring
        // alive until stopCopying has taken the pointer back.
        let status = AudioUnitAddRenderNotify(
            passThrough.audioUnit, copyToRing, Unmanaged.passUnretained(ring).toOpaque())
        guard status == noErr else {
            throw ListeningProblem(message: "“\(title)” can't be listened to.")
        }
    }

    /// Only call with the engine stopped, so the audio thread isn't mid-copy.
    private func stopCopying() {
        guard isCopying else { return }
        isCopying = false
        AudioUnitRemoveRenderNotify(
            passThrough.audioUnit, copyToRing, Unmanaged.passUnretained(ring).toOpaque())
    }
}

/// Runs on Core Audio's real-time thread, before and after each small block of sound
/// passes through. Afterwards, `data` is that block: copy it to the ring.
/// Nothing here may allocate memory, lock, or wait (CLAUDE.md rule 6).
private let copyToRing: AURenderCallback = { ringPointer, actions, _, _, frameCount, data in
    guard actions.pointee.contains(.unitRenderAction_PostRender), let data else { return noErr }
    let ring = Unmanaged<SampleRing>.fromOpaque(ringPointer).takeUnretainedValue()
    if actions.pointee.contains(.unitRenderAction_OutputIsSilence) {
        ring.writeSilence(count: Int(frameCount))
    } else {
        ring.write(UnsafeMutableAudioBufferListPointer(data), frameCount: Int(frameCount))
    }
    return noErr
}
