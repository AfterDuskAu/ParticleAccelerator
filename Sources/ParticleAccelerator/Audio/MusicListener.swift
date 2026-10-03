import AVFoundation
import Observation

/// Hears the music and measures it for the visuals.
///
/// It can listen to one of four things: a song file, which it plays itself; whatever
/// this Mac is playing; a microphone; or a host app's `AVPlayer`. Starting one stops
/// the one before.
///
/// It never changes the sound, writes no files and uses no network.
@MainActor
@Observable
public final class MusicListener {
    /// The kinds of thing the listener can listen to.
    public enum Source: Equatable, Sendable {
        case nothing, songFile, thisMac, microphone, player
    }

    /// What's being listened to now.
    public private(set) var source: Source = .nothing
    /// A name for it to show a person: the song's name, "This Mac's sound", or the
    /// microphone's name. Nil when there's nothing to name.
    public private(set) var sourceName: String?
    /// Something the person should know: a player's stream that can't be heard, or a
    /// different microphone being used than the one they chose. Nil when there's
    /// nothing to say.
    public private(set) var problem: String?

    /// The loaded song's name (its file name), or nil when no song file is loaded.
    public private(set) var songTitle: String?
    /// Whether a song file is playing.
    public private(set) var isPlaying: Bool = false
    /// The loaded song's length in seconds, or 0 when no song file is loaded.
    public private(set) var duration: TimeInterval = 0

    /// Silences the speakers for a song file. The visuals still hear the song and move
    /// to it. (The other sources aren't the listener's to silence.)
    public var isMuted: Bool = false {
        didSet { playback?.isMuted = isMuted }
    }

    /// Shows the visuals this many seconds later than the listener would by itself, or
    /// earlier if negative. The listener already allows for how long the Mac's output
    /// takes to play; this covers whatever is left (a TV that's slow to show the
    /// picture, say). It can't run ahead of sound that hasn't happened yet.
    public var timingOffset: TimeInterval = 0 {
        didSet {
            let allowed = min(0.5, max(-0.5, timingOffset))
            if allowed != timingOffset { timingOffset = allowed }
        }
    }

    /// Where the song file is, in seconds. It changes all the time while playing, so
    /// read it when drawing rather than waiting to be told it changed.
    public var currentTime: TimeInterval { playback?.currentTime ?? 0 }

    @ObservationIgnored private var feed: SoundFeed?
    /// The same feed, when it's a song file.
    @ObservationIgnored private var playback: SongFilePlayback?
    @ObservationIgnored private var analyser: SoundAnalyser?

    public init() {}

    // MARK: A song file

    /// Plays a song file from its start and listens to it.
    ///
    /// Throws an error whose `localizedDescription` says in plain English why the file
    /// can't be played.
    public func play(songFile url: URL) throws {
        try load(songFile: url)
        try resume()
    }

    public func pause() {
        playback?.pause()
        isPlaying = false
    }

    /// Carries on after `pause`, or starts again after the song has ended.
    public func resume() throws {
        guard let playback else { return }
        try playback.play()
        isPlaying = true
    }

    public func seek(to seconds: TimeInterval) {
        playback?.seek(to: seconds)
    }

    /// Opens a song file, ready to play, without making a sound.
    func load(songFile url: URL) throws {
        let newPlayback = try SongFilePlayback(url: url)
        stop()
        newPlayback.onStopped = { [weak self] in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
        newPlayback.isMuted = isMuted
        playback = newPlayback
        feed = newPlayback
        source = .songFile
        sourceName = newPlayback.title
        songTitle = newPlayback.title
        duration = newPlayback.duration
    }

    // MARK: The other sources

    /// Listens to whatever this Mac is playing: Spotify, a browser, any app. It needs
    /// macOS 14.2 or later, and the first time macOS asks the person to allow it.
    ///
    /// Throws an error whose `localizedDescription` says in plain English what's wrong.
    public func listenToThisMac() throws {
        guard #available(macOS 14.2, *) else {
            throw ListeningProblem(message: "Hearing this Mac's own sound needs macOS 14.2 or later.")
        }
        let newFeed = try MacSoundFeed()
        stop()
        feed = newFeed
        source = .thisMac
        sourceName = "This Mac's sound"
    }

    /// Listens to the microphone or line input chosen in System Settings → Sound →
    /// Input. The first time, macOS asks the person to allow it.
    ///
    /// If the chosen input is a Bluetooth headset, the Mac's own microphone is used
    /// instead and `problem` says so: listening to the headset would switch it to call
    /// quality.
    ///
    /// Throws an error whose `localizedDescription` says in plain English what's wrong.
    public func listenToMicrophone() async throws {
        // Check there's an input worth asking about before macOS asks the person.
        _ = try MicrophoneFeed.chooseInput()
        guard await MicrophoneFeed.askPermission() else {
            throw ListeningProblem(
                message: "The microphone can't be heard until you allow it in System Settings → Privacy & Security → Microphone.")
        }
        let newFeed = try MicrophoneFeed()
        stop()
        newFeed.onInputChanged = { [weak self, weak newFeed] in
            MainActor.assumeIsolated {
                self?.sourceName = newFeed?.inputName
                self?.problem = newFeed?.note
            }
        }
        feed = newFeed
        source = .microphone
        sourceName = newFeed.inputName
        problem = newFeed.note
    }

    /// Listens to a host app's player: whatever it plays now and whatever it plays
    /// next. The player's sound, volume and seeking are left alone. If an item's sound
    /// can't be heard, `problem` says why.
    ///
    /// Hand the player over once, early, and leave it handed over: handing over a
    /// player that's already playing makes the song stop for about half a second.
    /// A player turned down with `volume = 0` is still heard; one muted with `isMuted`
    /// goes quiet to the visuals after about four seconds (that's how macOS mutes).
    public func listen(to player: AVPlayer) {
        stop()
        let newFeed = PlayerFeed(player: player)
        newFeed.onProblem = { [weak self] message in
            MainActor.assumeIsolated { self?.problem = message }
        }
        feed = newFeed
        source = .player
    }

    /// Stops listening, and forgets the song file if there is one.
    public func stop() {
        feed?.shutDown()
        feed = nil
        playback = nil
        analyser = nil
        source = .nothing
        sourceName = nil
        problem = nil
        songTitle = nil
        duration = 0
        isPlaying = false
    }

    // MARK: For the visuals

    /// What the music is doing right now. Call it once a frame, from the main thread.
    func reading() -> SoundReading {
        guard let feed else { return .silence }
        let ring = feed.ring
        if analyser?.ring !== ring {
            analyser = SoundAnalyser(ring: ring)
        }
        guard let analyser else { return .silence }
        let later = Int64((timingOffset * ring.sampleRate).rounded())
        let reading = analyser.update(upTo: feed.heardUpTo - later)
        return feed.isHeldStill ? reading.quieted : reading
    }
}
