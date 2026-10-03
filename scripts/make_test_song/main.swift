// Writes the made-up test song (Tests/ParticleAcceleratorTests/TestSong.swift) to a
// sound file. Run it with scripts/make_test_song.sh.
import AVFoundation

guard CommandLine.arguments.count == 2 else {
    print("Say where to write the song, for example: build/Test Song 124.wav")
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let song = TestSong.samples()

guard let format = AVAudioFormat(standardFormatWithSampleRate: TestSong.sampleRate, channels: 2),
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(song.count)),
    let channels = buffer.floatChannelData
else {
    print("The song couldn't be made: this Mac wouldn't set up a sound buffer for it.")
    exit(1)
}
buffer.frameLength = AVAudioFrameCount(song.count)
for channel in 0..<2 {
    for (index, sample) in song.enumerated() { channels[channel][index] = sample }
}

do {
    // Ordinary CD-style sound: 16 bits, 44,100 samples a second, stereo.
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: TestSong.sampleRate,
        AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    ]
    try AVAudioFile(forWriting: url, settings: settings).write(from: buffer)
} catch {
    print("The song couldn't be written to \(url.path): \(error.localizedDescription)")
    exit(1)
}
print("Wrote \(url.path)")
print("\(Int(TestSong.seconds)) seconds at \(Int(TestSong.beatsPerMinute)) beats a minute, \(TestSong.kickTimes.count) kicks.")
