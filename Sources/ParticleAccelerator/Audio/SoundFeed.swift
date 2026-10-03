/// Somewhere the sound comes from: a song file, this Mac's own sound, a microphone or a
/// host app's player. Each one puts what it hears into a ring for the analyser, so
/// every visual works with every one of them.
///
/// Use a feed from the main thread only.
protocol SoundFeed: AnyObject {
    /// The sound heard so far. A feed swaps in a new ring when the sound's sample rate
    /// changes (a new song in a host's player, say).
    var ring: SampleRing { get }

    /// The number of the sample reaching the person's ears right now.
    ///
    /// Most feeds hear the sound a little before the speakers play it, so this is
    /// behind the newest sample in the ring. Measuring only up to here keeps the
    /// visuals in time with what's heard.
    var heardUpTo: Int64 { get }

    /// True while the sound is held still (a paused player), so the readings should go
    /// quiet rather than freeze on the last note.
    var isHeldStill: Bool { get }

    /// Stops listening for good and lets go of everything it took.
    func shutDown()
}
