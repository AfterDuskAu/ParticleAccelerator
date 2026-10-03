import AtomicIntegers
import CoreAudio

/// The last second or so of sound, handed from the audio thread to the analyser.
///
/// The audio thread writes and never waits: no lock, no memory allocation, and when the
/// ring is full it writes over the oldest sound. The analyser reads whichever stretch it
/// wants and is told if that stretch has already been written over. Only one thread may
/// write and only one may read.
///
/// The sound is kept as one channel (left and right averaged), which is all the
/// analyser needs.
final class SampleRing: @unchecked Sendable {
    /// How many samples the ring holds: about 1.5 seconds at 44,100 a second.
    static let capacity = 65_536

    /// The newest part of the ring a writer may be in the middle of changing, so a
    /// reader never trusts the oldest quarter. One write is never longer than this.
    private static let writerMargin = capacity / 4

    /// How many samples a second the sound in this ring has.
    let sampleRate: Double

    private let samples: UnsafeMutablePointer<Float>
    /// How many samples have ever been written. Sample number `n` lives at `n % capacity`.
    private let writtenCount: UnsafeMutablePointer<Int64>
    private let mask = Int64(capacity - 1)

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        samples = .allocate(capacity: Self.capacity)
        samples.initialize(repeating: 0, count: Self.capacity)
        writtenCount = .allocate(capacity: 1)
        writtenCount.initialize(to: 0)
    }

    deinit {
        samples.deallocate()
        writtenCount.deallocate()
    }

    // MARK: Writing (the audio thread)

    /// Adds what Core Audio just played. Safe on the real-time audio thread.
    func write(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int) {
        guard frameCount > 0, frameCount <= Self.writerMargin, let first = buffers.first,
            let firstData = first.mData
        else { return }
        let left = firstData.assumingMemoryBound(to: Float.self)
        let start = writtenCount.pointee

        if first.mNumberChannels >= 2 {
            // One buffer with the channels interleaved: left, right, left, right…
            let step = Int(first.mNumberChannels)
            for frame in 0..<frameCount {
                let mixed = (left[frame * step] + left[frame * step + 1]) * 0.5
                samples[Int((start + Int64(frame)) & mask)] = mixed
            }
        } else if buffers.count >= 2, let secondData = buffers[1].mData {
            // One buffer for each channel. Only the first two (front left and right) are
            // used, so an audio interface with spare outputs doesn't water the sound down.
            let right = secondData.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                samples[Int((start + Int64(frame)) & mask)] = (left[frame] + right[frame]) * 0.5
            }
        } else {
            for frame in 0..<frameCount {
                samples[Int((start + Int64(frame)) & mask)] = left[frame]
            }
        }
        pa_atomic_store_release(writtenCount, start + Int64(frameCount))
    }

    /// Adds one channel of sound. Safe on the real-time audio thread.
    func write(_ mono: UnsafePointer<Float>, count: Int) {
        guard count > 0, count <= Self.writerMargin else { return }
        let start = writtenCount.pointee
        for index in 0..<count {
            samples[Int((start + Int64(index)) & mask)] = mono[index]
        }
        pa_atomic_store_release(writtenCount, start + Int64(count))
    }

    /// Adds silence. Safe on the real-time audio thread.
    func writeSilence(count: Int) {
        guard count > 0, count <= Self.writerMargin else { return }
        let start = writtenCount.pointee
        for index in 0..<count {
            samples[Int((start + Int64(index)) & mask)] = 0
        }
        pa_atomic_store_release(writtenCount, start + Int64(count))
    }

    // MARK: Reading (the analyser)

    /// How many samples have been written since the ring was made.
    var totalWritten: Int64 { pa_atomic_load_acquire(writtenCount) }

    /// Copies the `count` samples that end just before sample number `end`.
    ///
    /// Sample numbers below zero (before the sound began) read as silence. Returns false,
    /// and the copy mustn't be used, if `end` hasn't been written yet or the stretch was
    /// written over before it could be copied.
    func read(endingAt end: Int64, count: Int, into destination: UnsafeMutablePointer<Float>)
        -> Bool
    {
        guard end <= totalWritten else { return false }
        let start = end - Int64(count)
        for index in 0..<count {
            let number = start + Int64(index)
            destination[index] = number < 0 ? 0 : samples[Int(number & mask)]
        }
        // The writer may have lapped the reader during the copy: check afterwards.
        return max(start, 0) >= oldestReadable
    }

    /// The oldest sample number `read` can still start from.
    var oldestReadable: Int64 {
        max(0, totalWritten - Int64(Self.capacity - Self.writerMargin))
    }
}
