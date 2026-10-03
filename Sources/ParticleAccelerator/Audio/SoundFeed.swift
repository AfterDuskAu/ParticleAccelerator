/// What a feed has heard so far.
struct Heard {
    /// The sound heard so far. A feed swaps in a new ring when the sound's sample rate
    /// changes (a new song in a host's player, say).
    let ring: SampleRing

    /// The number of the sample reaching the person's ears right now.
    ///
    /// Most feeds hear the sound a little before the speakers play it, so this is
    /// behind the newest sample in the ring. Measuring only up to here keeps the
    /// visuals in time with what's heard.
    let upTo: Int64

    /// True while the sound is held still (a paused player), so the readings should go
    /// quiet rather than freeze on the last note.
    let isHeldStill: Bool
}

/// Somewhere the sound comes from: a song file, this Mac's own sound, a microphone or a
/// host app's player. Each one puts what it hears into a ring for the analyser, so
/// every visual works with every one of them.
///
/// Use a feed from the main thread only, except for `heard`.
protocol SoundFeed: AnyObject {
    /// What's been heard so far. Safe to call from any thread: the stage asks from its
    /// own thread for every frame, so that drawing never waits for the main thread
    /// (CLAUDE.md rule 6).
    func heard() -> Heard

    /// Stops listening for good and lets go of everything it took.
    func shutDown()
}

extension SoundFeed {
    var ring: SampleRing { heard().ring }
    var heardUpTo: Int64 { heard().upTo }
    var isHeldStill: Bool { heard().isHeldStill }
}
