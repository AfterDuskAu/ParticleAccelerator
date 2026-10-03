import AVFoundation
import Testing

@testable import ParticleAccelerator

private func counting(from first: Int, count: Int) -> [Float] {
    (first..<(first + count)).map { Float($0) }
}

private func read(_ ring: SampleRing, endingAt end: Int64, count: Int) -> [Float]? {
    var copy = [Float](repeating: -1, count: count)
    let fine = copy.withUnsafeMutableBufferPointer {
        ring.read(endingAt: end, count: count, into: $0.baseAddress!)
    }
    return fine ? copy : nil
}

@Test func theRingGivesBackWhatWasWritten() {
    let ring = SampleRing(sampleRate: 44_100)
    ring.write(counting(from: 0, count: 1_000), count: 1_000)
    #expect(ring.totalWritten == 1_000)
    #expect(read(ring, endingAt: 1_000, count: 512) == counting(from: 488, count: 512))
    #expect(read(ring, endingAt: 600, count: 100) == counting(from: 500, count: 100))
}

@Test func beforeTheSoundBeganReadsAsSilence() {
    let ring = SampleRing(sampleRate: 44_100)
    ring.write(counting(from: 1, count: 3), count: 3)
    #expect(read(ring, endingAt: 3, count: 6) == [0, 0, 0, 1, 2, 3])
}

@Test func soundNotYetWrittenCantBeRead() {
    let ring = SampleRing(sampleRate: 44_100)
    ring.write(counting(from: 0, count: 100), count: 100)
    #expect(read(ring, endingAt: 101, count: 10) == nil)
}

@Test func theRingKeepsTheNewestSoundAfterWrappingRound() {
    let ring = SampleRing(sampleRate: 44_100)
    // Three times round the ring, in the chunks Core Audio hands over.
    let total = SampleRing.capacity * 3 + 300
    var written = 0
    while written < total {
        let count = min(512, total - written)
        ring.write(counting(from: written, count: count), count: count)
        written += count
    }
    #expect(ring.totalWritten == Int64(total))
    #expect(read(ring, endingAt: Int64(total), count: 2_048) == counting(from: total - 2_048, count: 2_048))
}

@Test func soundThatWasWrittenOverIsRefusedNotReturnedWrong() {
    let ring = SampleRing(sampleRate: 44_100)
    let total = SampleRing.capacity * 2
    var written = 0
    while written < total {
        ring.write(counting(from: written, count: 512), count: 512)
        written += 512
    }
    #expect(read(ring, endingAt: 10_000, count: 512) == nil)
    #expect(read(ring, endingAt: ring.oldestReadable + 512, count: 512) != nil)
}

@Test func leftAndRightAreAveragedIntoOneChannel() throws {
    let ring = SampleRing(sampleRate: 44_100)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
    buffer.frameLength = 4
    let channels = try #require(buffer.floatChannelData)
    for frame in 0..<4 {
        channels[0][frame] = 1
        channels[1][frame] = Float(frame)
    }
    ring.write(UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList), frameCount: 4)
    #expect(read(ring, endingAt: 4, count: 4) == [0.5, 1, 1.5, 2])
}

@Test func silenceCanBeWritten() {
    let ring = SampleRing(sampleRate: 44_100)
    ring.write(counting(from: 5, count: 4), count: 4)
    ring.writeSilence(count: 4)
    #expect(read(ring, endingAt: 8, count: 8) == [5, 6, 7, 8, 0, 0, 0, 0])
}
