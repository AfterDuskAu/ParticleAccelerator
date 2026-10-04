import AVFoundation
import AtomicIntegers
import MediaToolbox
import os

/// Hears a host app's `AVPlayer`: whatever it plays now and whatever it plays next.
///
/// It adds a listening tap (an `MTAudioProcessingTap`) to the playing item's sound. The
/// tap passes the sound through untouched, and the host's playing, volume and seeking
/// are left alone.
///
/// Measured on 2026-10-03:
/// - The tap is handed the sound in blocks of about a twentieth of a second, almost
///   half a second before the speakers play it. So each block's place in the song is
///   kept, and what's been heard follows the playing item's own clock.
/// - That clock (the item's "timebase") agrees with the player's `currentTime()` to
///   within a millisecond while it plays, and unlike the player it may be read from
///   any thread. It runs at no speed while the player is paused or waiting.
/// - For about a quarter of a second after the player starts or seeks, the clock runs
///   up to the starting place from just before it, while `currentTime()` waits at the
///   starting place. Nothing is heard in that time, by either reckoning.
/// - A player turned down to nothing (`volume = 0`) is still heard. A player muted
///   with `isMuted` is heard for about four seconds, and then macOS hands the tap
///   silence for as long as it stays muted.
///
/// It works for files and for streams with a sound track of their own. A stream whose
/// sound can't be reached (HLS) gives a plain message through `onProblem`.
///
/// Use it from the main thread only, except for `heard`.
final class PlayerFeed: SoundFeed {
    /// Called with a plain-English message when an item's sound can't be heard, and
    /// with nil when the next one can.
    var onProblem: ((String?) -> Void)?

    private let player: AVPlayer
    private var itemWatch: NSKeyValueObservation?
    private var clockWatch: NSKeyValueObservation?
    private var attachment: Attachment?
    private var isShutDown = false
    /// Stands in until the first item's sound arrives.
    private let emptyRing = SampleRing(sampleRate: 44_100)
    /// What `heard` needs from the item being listened to. The stage's thread reads it
    /// while the main thread may be changing it (the next song).
    private let heardFrom = OSAllocatedUnfairLock<HeardFrom?>(uncheckedState: nil)

    private struct HeardFrom {
        let context: PlayerTapContext
        /// The item's own clock, or nil if it hasn't one yet.
        var clock: CMTimebase?
    }

    private struct Attachment {
        let item: AVPlayerItem
        let tap: MTAudioProcessingTap
        let context: PlayerTapContext
        /// The item's own sound settings from before the tap was added, to put back.
        let mixBefore: AVAudioMix?
    }

    init(player: AVPlayer) {
        self.player = player
        itemWatch = player.observe(\.currentItem) { [weak self] _, _ in
            DispatchQueue.main.async { self?.currentItemChanged() }
        }
        currentItemChanged()
    }

    func heard() -> Heard {
        guard let from = heardFrom.withLockUnchecked({ $0 }) else {
            return Heard(ring: emptyRing, upTo: 0, isHeldStill: true)
        }
        let ownRing = from.context.ring
        guard let clock = from.clock else {
            return Heard(ring: ownRing ?? emptyRing, upTo: 0, isHeldStill: true)
        }
        // The clock runs at no speed while the player is paused or waiting for more
        // of a stream.
        let isHeldStill = CMTimebaseGetRate(clock) == 0
        let offset = from.context.timeOffset
        let now = CMTimebaseGetTime(clock).seconds
        guard let ring = ownRing, offset.isFinite, now.isFinite else {
            return Heard(ring: ownRing ?? emptyRing, upTo: 0, isHeldStill: isHeldStill)
        }
        return Heard(
            ring: ring, upTo: Int64(((now - offset) * ring.sampleRate).rounded()), isHeldStill: isHeldStill)
    }

    /// Where the ring's samples sit in the song: a sample's time in the song is its
    /// number ÷ the sample rate + this many seconds. Nil until the first sound arrives.
    var timeOffset: Double? {
        guard let offset = attachment?.context.timeOffset, offset.isFinite else { return nil }
        return offset
    }

    func shutDown() {
        isShutDown = true
        itemWatch?.invalidate()
        itemWatch = nil
        detach()
    }

    // MARK: Following the player

    private func currentItemChanged() {
        guard !isShutDown, player.currentItem !== attachment?.item else { return }
        detach()
        guard let item = player.currentItem else { return }
        // A stream's tracks aren't known until some of it has loaded. This is
        // AVFoundation's plain callback, so the tap goes on promptly however busy the
        // app is: put on late, it would make the song hiccup (see attach).
        item.asset.loadTracks(withMediaType: .audio) { [weak self] tracks, _ in
            DispatchQueue.main.async {
                guard let self, !self.isShutDown, self.player.currentItem === item,
                    self.attachment == nil
                else { return }
                self.attach(to: item, track: tracks?.first)
            }
        }
    }

    /// Adds the tap to an item's sound.
    ///
    /// Measured on 2026-10-03: added to an item that's already playing, the player
    /// stops for about half a second while it sets its sound up again. Added before
    /// the item starts, nothing is heard. So a host should hand its player over once,
    /// early, and leave it handed over.
    private func attach(to item: AVPlayerItem, track: AVAssetTrack?) {
        guard let track else {
            onProblem?(
                "This player's sound can't be heard: it's a kind of stream that keeps its sound out of reach (live and HLS streams do).")
            return
        }
        let mixBefore = item.audioMix
        let others = mixBefore?.inputParameters.filter { $0.trackID != track.trackID } ?? []
        let parameters: AVMutableAudioMixInputParameters
        if let existing = mixBefore?.inputParameters.first(where: { $0.trackID == track.trackID }) {
            guard existing.audioTapProcessor == nil,
                let copy = existing.mutableCopy() as? AVMutableAudioMixInputParameters
            else {
                onProblem?("This player's sound can't be heard: the app playing it is already listening to it with a tap of its own.")
                return
            }
            // Keep the host's own volume settings for the track.
            parameters = copy
        } else {
            parameters = AVMutableAudioMixInputParameters(track: track)
        }

        let context = PlayerTapContext()
        guard let tap = makeTap(for: context) else {
            onProblem?("This player's sound can't be heard: the listening tap couldn't be made.")
            return
        }
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = others + [parameters]
        item.audioMix = mix
        attachment = Attachment(item: item, tap: tap, context: context, mixBefore: mixBefore)
        let from = HeardFrom(context: context, clock: item.timebase)
        heardFrom.withLockUnchecked { $0 = from }
        if from.clock == nil {
            // An item has had its clock from the moment it was made whenever this was
            // tried (2026-10-03). If one ever hasn't, take it when the item is ready.
            clockWatch = item.observe(\.status) { [weak self] item, _ in
                DispatchQueue.main.async { self?.takeClock(of: item) }
            }
        }
        onProblem?(nil)
    }

    private func takeClock(of item: AVPlayerItem) {
        guard attachment?.item === item, let clock = item.timebase else { return }
        clockWatch = nil
        heardFrom.withLockUnchecked { $0?.clock = clock }
    }

    /// Takes the tap off again, unless the host has changed the item's sound settings
    /// since, in which case they're the host's to keep.
    private func detach() {
        guard let attachment else { return }
        self.attachment = nil
        clockWatch = nil
        heardFrom.withLockUnchecked { $0 = nil }
        let stillOurs = attachment.item.audioMix?.inputParameters.contains {
            $0.audioTapProcessor === attachment.tap
        }
        if stillOurs == true {
            attachment.item.audioMix = attachment.mixBefore
        }
    }
}

// MARK: - The tap

/// What one tap shares between the audio thread, which fills the ring, and the main
/// thread, which reads it. The tap keeps it alive for as long as the tap lives.
final class PlayerTapContext: @unchecked Sendable {
    private let lock = NSLock()
    private var currentRing: SampleRing?
    /// The same ring, for the audio thread only: set before the first block of sound
    /// arrives and cleared after the last, never while one is being handled.
    private var audioThreadRing: SampleRing?
    /// Where the ring's samples sit in the song: a sample's time in the song is its
    /// number ÷ the sample rate + this many seconds. Stored as the raw bits of a
    /// Double, so the audio thread can change it without a lock. "Not a number" until
    /// the first block arrives.
    private let timeOffsetBits: UnsafeMutablePointer<Int64>

    init() {
        timeOffsetBits = .allocate(capacity: 1)
        timeOffsetBits.initialize(to: Int64(bitPattern: Double.nan.bitPattern))
    }

    deinit {
        timeOffsetBits.deallocate()
    }

    /// The ring the tap is filling, once the tap knows the sound's sample rate.
    var ring: SampleRing? {
        lock.lock()
        defer { lock.unlock() }
        return currentRing
    }

    var timeOffset: Double {
        Double(bitPattern: UInt64(bitPattern: pa_atomic_load_acquire(timeOffsetBits)))
    }

    /// The tap is about to start handing over sound in this format. A player does this
    /// again whenever it sets its sound up afresh (after a stall or a seek), so the
    /// ring is kept unless the sample rate has changed: a new ring would make the
    /// analyser forget the tempo.
    fileprivate func prepare(for format: AudioStreamBasicDescription) {
        lock.lock()
        if !DeviceListening.isUsualFormat(format) || format.mSampleRate <= 0 {
            currentRing = nil
        } else if currentRing?.sampleRate != format.mSampleRate {
            currentRing = SampleRing(sampleRate: format.mSampleRate)
        }
        let ring = currentRing
        lock.unlock()
        audioThreadRing = ring
        pa_atomic_store_release(timeOffsetBits, Int64(bitPattern: Double.nan.bitPattern))
    }

    fileprivate func unprepare() {
        audioThreadRing = nil
    }

    /// One block of sound, on the real-time audio thread: no allocation, no lock, no
    /// waiting (CLAUDE.md rule 6).
    fileprivate func heard(
        _ buffers: UnsafeMutablePointer<AudioBufferList>, frameCount: Int, startingAt start: CMTime
    ) {
        guard let ring = audioThreadRing else { return }
        // The very first block is a warm-up with no place in the song: skip it.
        let startSeconds = CMTimeGetSeconds(start)
        guard startSeconds.isFinite else { return }
        let offset = startSeconds - Double(ring.totalWritten) / ring.sampleRate
        pa_atomic_store_release(timeOffsetBits, Int64(bitPattern: offset.bitPattern))
        ring.write(UnsafeMutableAudioBufferListPointer(buffers), frameCount: frameCount)
    }
}

private func makeTap(for context: PlayerTapContext) -> MTAudioProcessingTap? {
    // The tap takes over one hold on the context, and lets go of it in tapFinalize.
    let held = Unmanaged.passRetained(context)
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: held.toOpaque(),
        init: tapInit, finalize: tapFinalize, prepare: tapPrepare, unprepare: tapUnprepare,
        process: tapProcess)
    // "Pre-effects": the sound as it is in the song, before the player's own volume.
    let made = whatWasMade { tapOut in
        MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, tapOut)
    }
    guard let made else {
        held.release()
        return nil
    }
    return tapToKeep(made)
}

// Apple changed how `MTAudioProcessingTapCreate` hands back the tap. Xcode 16's SDK hands
// back an `Unmanaged<MTAudioProcessingTap>`, which the caller must take hold of; Xcode
// 26's hands back the tap itself. These three build with either, with no version to
// keep in step: `Made` is whichever the SDK says, and `tapToKeep` is chosen to match.
// (CI's Intel Mac has Xcode 16, and the first build there failed on this, 2026-10-04.)

/// Calls a function that hands back what it made through a pointer, and gives what it
/// made, or nil if it said it failed.
private func whatWasMade<Made>(by create: (UnsafeMutablePointer<Made?>) -> OSStatus) -> Made? {
    var made: Made?
    return create(&made) == noErr ? made : nil
}

private func tapToKeep(_ tap: MTAudioProcessingTap) -> MTAudioProcessingTap { tap }

private func tapToKeep(_ tap: Unmanaged<MTAudioProcessingTap>) -> MTAudioProcessingTap {
    tap.takeRetainedValue()
}

private func context(of tap: MTAudioProcessingTap) -> PlayerTapContext {
    Unmanaged<PlayerTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<PlayerTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    context(of: tap).prepare(for: format.pointee)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    context(of: tap).unprepare()
}

private let tapProcess: MTAudioProcessingTapProcessCallback = {
    tap, frameCount, _, buffers, frameCountOut, flagsOut in
    var timeRange = CMTimeRange()
    // Fetching the sound into `buffers` is also what passes it on to the speakers.
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, frameCount, buffers, flagsOut, &timeRange, frameCountOut)
    guard status == noErr else {
        frameCountOut.pointee = 0
        return
    }
    context(of: tap).heard(buffers, frameCount: frameCountOut.pointee, startingAt: timeRange.start)
}
