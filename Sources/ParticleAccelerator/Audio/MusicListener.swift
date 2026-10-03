import Foundation
import Observation

/// Hears the music and measures it for the visuals.
///
/// For now it hears a song file, which it plays itself. The Mac's own sound, a
/// microphone and a host app's player follow (docs/PLAN.md, phase 1).
///
/// It never changes the sound, writes no files and uses no network.
@MainActor
@Observable
public final class MusicListener {
    /// The loaded song's name (its file name), or nil when no song is loaded.
    public private(set) var songTitle: String?
    public private(set) var isPlaying: Bool = false
    /// The loaded song's length in seconds, or 0 when no song is loaded.
    public private(set) var duration: TimeInterval = 0

    /// Silences the speakers. The visuals still hear the song and move to it.
    public var isMuted: Bool = false {
        didSet { playback?.isMuted = isMuted }
    }

    /// Where the song is, in seconds. It changes all the time while playing, so read it
    /// when drawing rather than waiting to be told it changed.
    public var currentTime: TimeInterval { playback?.currentTime ?? 0 }

    @ObservationIgnored private var playback: SongFilePlayback?
    @ObservationIgnored private var analyser: SoundAnalyser?

    public init() {}

    /// Plays a song file from its start and listens to it. Any song already playing
    /// stops.
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

    /// Stops playing and forgets the song.
    public func stop() {
        playback?.shutDown()
        playback = nil
        analyser = nil
        songTitle = nil
        duration = 0
        isPlaying = false
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
        songTitle = newPlayback.title
        duration = newPlayback.duration
    }

    /// What the music is doing right now. Call it once a frame, from the main thread.
    func reading() -> SoundReading {
        guard let playback else { return .silence }
        if analyser?.ring !== playback.ring {
            analyser = SoundAnalyser(ring: playback.ring)
        }
        return analyser?.update() ?? .silence
    }
}
