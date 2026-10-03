import Foundation
import Testing
import os

@testable import ParticleAccelerator

// MARK: The stage's own thread

@Test func workHandedToTheStagesThreadRunsThereInOrder() {
    let stage = StageThread(name: "Test stage")
    defer { stage.stop() }
    let seen = OSAllocatedUnfairLock(initialState: (order: [Int](), onMainThread: 0, names: Set<String>()))
    let done = DispatchSemaphore(value: 0)
    for number in 0..<200 {
        stage.perform {
            seen.withLock {
                $0.order.append(number)
                if Thread.isMainThread { $0.onMainThread += 1 }
                $0.names.insert(Thread.current.name ?? "")
            }
            if number == 199 { done.signal() }
        }
    }
    #expect(done.wait(timeout: .now() + 20) == .success)
    let result = seen.withLock { $0 }
    #expect(result.order == Array(0..<200))
    #expect(result.onMainThread == 0)
    #expect(result.names == ["Test stage"])
}

@Test func theStagesThreadFinishesItsWorkAndThenEnds() {
    let stage = StageThread(name: "Test stage")
    let count = OSAllocatedUnfairLock(initialState: 0)
    for _ in 0..<20 { stage.perform { count.withLock { $0 += 1 } } }
    #expect(!stage.hasEnded)
    stage.stop()
    // It ends by itself, having done everything it was handed first.
    let deadline = Date().addingTimeInterval(20)
    while !stage.hasEnded, Date() < deadline { usleep(2_000) }
    #expect(stage.hasEnded)
    #expect(count.withLock { $0 } == 20)
}

// MARK: How often it draws

@Test func theStageIdlesAfterThreeSecondsOfSilenceAndWakesAtOnce() {
    var pacing = FramePacing()
    // Just started, with nothing playing: full speed for the first three seconds.
    #expect(pacing.rate(at: 100, loudness: 0) == 60)
    #expect(pacing.rate(at: 102.9, loudness: 0) == 60)
    #expect(pacing.rate(at: 103.1, loudness: 0) == 20)
    // The moment there's sound, full speed again.
    #expect(pacing.rate(at: 103.2, loudness: 0.4) == 60)
    #expect(pacing.rate(at: 106.1, loudness: 0) == 60)
    #expect(pacing.rate(at: 106.3, loudness: 0) == 20)
}

// MARK: Readings, asked for from more than one thread

/// A feed the test fills by hand.
private final class HandFedFeed: SoundFeed {
    let handRing = SampleRing(sampleRate: TestSound.sampleRate)
    let isHeld = OSAllocatedUnfairLock(initialState: false)

    func heard() -> Heard {
        Heard(ring: handRing, upTo: handRing.totalWritten, isHeldStill: isHeld.withLock { $0 })
    }

    func shutDown() {}

    func write(_ sound: [Float]) {
        sound.withUnsafeBufferPointer { handRing.write($0.baseAddress!, count: $0.count) }
    }
}

@Test func withNothingToListenToTheReadingsAreSilence() {
    let readings = Readings()
    #expect(readings.reading() == .silence)
    let feed = HandFedFeed()
    readings.listen(to: feed)
    feed.write(TestSound.sine(hz: 100, amplitude: 0.5, seconds: 1))
    #expect(readings.reading().loudness > 0)
    readings.listen(to: nil)
    #expect(readings.reading() == .silence)
}

@Test func aFeedHeldStillGivesQuietReadingsThatKeepTheirPlace() {
    let readings = Readings()
    let feed = HandFedFeed()
    readings.listen(to: feed)
    feed.write(TestSound.sine(hz: 100, amplitude: 0.5, seconds: 1))
    let playing = readings.reading()
    #expect(playing.loudness > 0)
    feed.isHeld.withLock { $0 = true }
    let held = readings.reading()
    #expect(held.loudness == 0 && held.bars == SIMD64<Float>(repeating: 0))
    #expect(held.seconds == playing.seconds)
}

@Test func aLaterTimingShowsTheSoundLater() {
    // A second of silence and then a tone. Shown a quarter of a second late, the tone
    // hasn't arrived yet when the last of the sound has.
    let feed = HandFedFeed()
    feed.write(TestSound.silence(seconds: 1) + TestSound.sine(hz: 100, amplitude: 0.5, seconds: 0.2))
    let onTime = Readings()
    onTime.listen(to: feed)
    #expect(onTime.reading().loudness > 0)

    let late = Readings()
    late.setTimingOffset(0.25)
    late.listen(to: feed)
    #expect(late.reading().loudness == 0)
}

@Test func readingsAskedForFromThreeThreadsAreTheSameAsFromOne() {
    let song = Array(TestSong.samples().prefix(Int(TestSound.sampleRate * 4)))
    // What one thread alone makes of the song's first four seconds.
    let alone = TestListener().hear(song)

    // The stage's thread and the main thread both ask, 60 times a second each. Here two
    // threads ask as fast as they can while the sound keeps arriving, and the thread
    // the sound arrives on asks as well.
    let feed = HandFedFeed()
    let readings = Readings()
    readings.listen(to: feed)
    let isArriving = OSAllocatedUnfairLock(initialState: true)
    let wentBackwards = OSAllocatedUnfairLock(initialState: 0)
    let finished = DispatchGroup()
    for _ in 0..<2 {
        finished.enter()
        Thread.detachNewThread {
            var last = 0.0
            while isArriving.withLock({ $0 }) {
                let seconds = readings.reading().seconds
                // The music only ever moves forwards.
                if seconds < last { wentBackwards.withLock { $0 += 1 } }
                last = seconds
            }
            finished.leave()
        }
    }

    // The sound arrives in the pieces Core Audio hands over. It never gets more than
    // half a second ahead of what's been measured, so that nothing is skipped however
    // slowly a busy computer gives the threads their turns.
    var start = 0
    while start < song.count {
        let count = min(512, song.count - start)
        feed.write(Array(song[start..<start + count]))
        start += count
        while Double(start) / TestSound.sampleRate - readings.reading().seconds > 0.5 { usleep(100) }
    }
    isArriving.withLock { $0 = false }
    #expect(finished.wait(timeout: .now() + 60) == .success)

    #expect(wentBackwards.withLock { $0 } == 0)
    // With everything in, the reading is the very one a single thread arrives at.
    #expect(readings.reading() == alone)
}
