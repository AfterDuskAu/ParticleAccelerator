import Foundation
import os

/// Turns what a feed has heard into readings, for whoever asks on whichever thread:
/// the stage asks from its own thread for every frame, and the sound check asks from
/// the main thread.
///
/// The analyser can only be worked by one thread at a time, so each asker waits its
/// turn. A turn is about a hundredth of a millisecond (docs/OUTPUT.md), and neither
/// asker is the audio thread, which never waits for anything.
final class Readings: @unchecked Sendable {
    private struct State {
        var feed: SoundFeed?
        var analyser: SoundAnalyser?
        var timingOffset: TimeInterval = 0
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// Starts measuring this feed, or nothing.
    func listen(to feed: SoundFeed?) {
        state.withLockUnchecked {
            $0.feed = feed
            $0.analyser = nil
        }
    }

    /// Shows the visuals this many seconds later than the feed says, or earlier if
    /// negative (`MusicListener.timingOffset`).
    func setTimingOffset(_ seconds: TimeInterval) {
        state.withLockUnchecked { $0.timingOffset = seconds }
    }

    /// What the music is doing right now. Call it once a frame, from any thread.
    func reading() -> SoundReading {
        state.withLockUnchecked { state in
            guard let feed = state.feed else { return .silence }
            let heard = feed.heard()
            if state.analyser?.ring !== heard.ring {
                state.analyser = SoundAnalyser(ring: heard.ring)
            }
            guard let analyser = state.analyser else { return .silence }
            let later = Int64((state.timingOffset * heard.ring.sampleRate).rounded())
            let reading = analyser.update(upTo: heard.upTo - later)
            return heard.isHeldStill ? reading.quieted : reading
        }
    }
}
