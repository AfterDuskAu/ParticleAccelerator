import AVFoundation
import Testing

@testable import ParticleAccelerator

// These tests play generated files in an AVPlayer turned down to nothing, the way a
// host app (Music Organizer) would hand its player over. They make no sound.
//
// The player is turned down with `volume = 0`, not `isMuted`: macOS stops handing a
// muted player's sound to the tap after about four seconds (measured 2026-10-03).

private let rate = 48_000.0

/// Three seconds: a 300 Hz tone (in the low mids) for the first half, then a 3 kHz
/// tone (in the vocals band). Left and right differ, to show both are heard.
private func twoToneFile(in folder: TemporaryFolder) throws -> (url: URL, mixed: [Float]) {
    let low = tone(hz: 300, amplitude: 0.5, seconds: 1.5, sampleRate: rate)
    let high = tone(hz: 3_000, amplitude: 0.5, seconds: 1.5, sampleRate: rate)
    let left = low + high
    let right = left.map { $0 * 0.5 }
    let url = folder.file("Two tones.caf")
    try writeSoundFile(left: left, right: right, sampleRate: rate, to: url)
    return (url, zip(left, right).map { ($0 + $1) * 0.5 })
}

/// The file as a "joined composition": the way a player plays sound and picture that
/// arrive as separate streams, as YouTube's do.
private func joinedComposition(of url: URL) async throws -> AVComposition {
    let asset = AVURLAsset(url: url)
    let soundTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let composition = AVMutableComposition()
    let track = try #require(
        composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
    try track.insertTimeRange(
        CMTimeRange(start: .zero, duration: try await asset.load(.duration)), of: soundTrack, at: .zero)
    return composition
}

/// Three seconds of hiss, different left and right. No two stretches of hiss are
/// alike, so any piece of it can be found again in the file.
private func hissFile(in folder: TemporaryFolder) throws -> (url: URL, mixed: [Float]) {
    let count = Int(rate * 3)
    let left = Array(TestSound.noise(amplitude: 0.5, seconds: 4, seed: 11).prefix(count))
    let right = Array(TestSound.noise(amplitude: 0.5, seconds: 4, seed: 12).prefix(count))
    let url = folder.file("Hiss.caf")
    try writeSoundFile(left: left, right: right, sampleRate: rate, to: url)
    return (url, zip(left, right).map { ($0 + $1) * 0.5 })
}

/// Plays an item muted to its end and checks that everything the feed heard is the
/// file's own samples, exactly and in order.
///
/// On a busy computer a player can stall and pick up again, so the check allows a few
/// restarts: after one, it finds its place in the file again and carries on.
@MainActor
private func expectHeardExactly(_ item: AVPlayerItem, mixed: [Float]) async throws {
    await waitForAQuietMoment()
    let player = AVPlayer(playerItem: item)
    player.volume = 0
    let feed = PlayerFeed(player: player)
    defer { feed.shutDown() }
    await wait(upTo: 20) { item.audioMix != nil }
    player.play()
    // The feed's own ring appears once the tap knows the sound's sample rate.
    await wait(upTo: 30) { feed.ring.sampleRate == rate }
    try #require(feed.ring.sampleRate == rate)
    let recorder = RingRecorder(ring: feed.ring)
    await wait(upTo: 30) {
        player.currentTime().seconds >= Double(mixed.count) / rate - 0.05
    }
    let heard = try #require(recorder.finish())
    try #require(heard.count > 100)

    // Where each pair of neighbouring samples is in the file.
    var places: [UInt64: Int] = [:]
    func key(_ one: Float, _ next: Float) -> UInt64 {
        UInt64(one.bitPattern) << 32 | UInt64(next.bitPattern)
    }
    for index in 0..<(mixed.count - 1) { places[key(mixed[index], mixed[index + 1])] = index }

    var place = -1  // where in the file the next sample should come from
    var matched = 0
    var restarts = 0
    var strangers = 0
    for number in 0..<(heard.count - 1) {
        if place >= 0, place < mixed.count, heard[number] == mixed[place] {
            matched += 1
            place += 1
        } else if let found = places[key(heard[number], heard[number + 1])] {
            restarts += 1
            matched += 1
            place = found + 1
        } else if heard[number] != 0 {
            // Not the file's sample and not silence: something changed the sound.
            strangers += 1
        }
    }
    #expect(strangers == 0)
    #expect(matched > Int(rate * 2.5), "only \(matched) samples matched")
    #expect(restarts <= 4, "\(restarts) restarts")
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func aHostsPlayerIsHeardSampleForSampleEvenWhenTurnedDownToNothing() async throws {
    let folder = try TemporaryFolder()
    let (url, mixed) = try hissFile(in: folder)
    try await expectHeardExactly(AVPlayerItem(url: url), mixed: mixed)
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func aJoinedCompositionIsHeardSampleForSample() async throws {
    let folder = try TemporaryFolder()
    let (url, mixed) = try hissFile(in: folder)
    try await expectHeardExactly(AVPlayerItem(asset: try await joinedComposition(of: url)), mixed: mixed)
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func theReadingsFollowThePlayersClockNotTheSoundThatArrivedEarly() async throws {
    await waitForAQuietMoment()
    let folder = try TemporaryFolder()
    let (url, _) = try twoToneFile(in: folder)
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.volume = 0
    let listener = MusicListener()
    listener.listen(to: player)
    defer { listener.stop() }
    #expect(listener.source == .player)
    await wait(upTo: 20) { item.audioMix != nil }

    // The player is handed the sound almost half a second early. If the readings used
    // it as it arrived, the high tone would show at 1.1 seconds instead of 1.5.
    var lowToneMoments = 0
    var highToneMoments = 0
    var wrongMoments: [Double] = []
    player.play()
    await wait(upTo: 30) {
        let reading = listener.reading()
        let time = player.currentTime().seconds
        let lowMids = reading.bandDecibels.lowMids
        let vocals = reading.bandDecibels.vocals
        // On a busy computer the player can stall for a moment: those moments read
        // quiet, and say nothing about timing.
        guard player.timeControlStatus == .playing else { return time > 2.9 }
        if time > 0.4, time < 1.4 {
            if lowMids > vocals + 20 { lowToneMoments += 1 } else { wrongMoments.append(time) }
        } else if time > 1.6, time < 2.8 {
            if vocals > lowMids + 20 { highToneMoments += 1 } else { wrongMoments.append(time) }
        }
        return time > 2.9
    }
    #expect(lowToneMoments > 5)
    #expect(highToneMoments > 5)
    #expect(wrongMoments.isEmpty, "wrong at \(wrongMoments)")
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func aPausedPlayerReadsQuietButKeepsItsPlace() async throws {
    await waitForAQuietMoment()
    let folder = try TemporaryFolder()
    let (url, _) = try twoToneFile(in: folder)
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.volume = 0
    let listener = MusicListener()
    listener.listen(to: player)
    defer { listener.stop() }
    await wait(upTo: 20) { item.audioMix != nil }

    player.play()
    var heardTheTone = false
    await wait(upTo: 30) {
        heardTheTone = listener.reading().bands.lowMids > 0.9
        return heardTheTone && player.currentTime().seconds > 0.6
    }
    #expect(heardTheTone)

    player.pause()
    await wait(upTo: 10) { player.timeControlStatus == .paused }
    let paused = listener.reading()
    #expect(paused.bands == BandValues())
    #expect(paused.loudness == 0)
    #expect(paused.seconds > 0.5)
}

@MainActor
@Test func theHostsOwnSoundSettingsAreKeptAndPutBack() async throws {
    await waitForAQuietMoment()
    let folder = try TemporaryFolder()
    let (url, _) = try twoToneFile(in: folder)
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
    let item = AVPlayerItem(asset: asset)

    // The host has turned this track down to half.
    let hostParameters = AVMutableAudioMixInputParameters(track: track)
    hostParameters.setVolume(0.5, at: .zero)
    let hostMix = AVMutableAudioMix()
    hostMix.inputParameters = [hostParameters]
    item.audioMix = hostMix

    func volumeAndTap() -> (volume: Float?, hasTap: Bool) {
        let parameters = item.audioMix?.inputParameters.first
        var start: Float = 0
        var end: Float = 0
        var range = CMTimeRange()
        let hasVolume = parameters?.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range) ?? false
        return (hasVolume ? start : nil, parameters?.audioTapProcessor != nil)
    }

    let player = AVPlayer(playerItem: item)
    let feed = PlayerFeed(player: player)
    await wait(upTo: 20) { volumeAndTap().hasTap }
    #expect(volumeAndTap().hasTap)
    #expect(volumeAndTap().volume == 0.5)

    feed.shutDown()
    #expect(volumeAndTap().hasTap == false)
    #expect(volumeAndTap().volume == 0.5)
}

@MainActor
@Test func withNoSettingsOfItsOwnTheItemIsLeftAsItWasFound() async throws {
    await waitForAQuietMoment()
    let folder = try TemporaryFolder()
    let (url, _) = try twoToneFile(in: folder)
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    let feed = PlayerFeed(player: player)
    await wait(upTo: 20) { item.audioMix != nil }
    #expect(item.audioMix != nil)
    feed.shutDown()
    #expect(item.audioMix == nil)
}

@MainActor
@Test func aStreamWhoseSoundCantBeReachedIsSaidPlainly() async throws {
    await waitForAQuietMoment()
    // An item with no sound track of its own, which is how an HLS stream looks.
    let player = AVPlayer(playerItem: AVPlayerItem(asset: AVMutableComposition()))
    let listener = MusicListener()
    listener.listen(to: player)
    defer { listener.stop() }
    await wait(upTo: 20) { listener.problem != nil }
    #expect(listener.problem?.contains("can't be heard") == true)
    #expect(listener.reading() == .silence)
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func theListenerFollowsThePlayerToItsNextSong() async throws {
    await waitForAQuietMoment()
    let folder = try TemporaryFolder()
    let (firstURL, _) = try twoToneFile(in: folder)
    // A second song at a different sample rate, with a 1 kHz tone (in the mids).
    let secondURL = folder.file("Second.caf")
    let second = tone(hz: 1_000, amplitude: 0.5, seconds: 2, sampleRate: 44_100)
    try writeSoundFile(left: second, right: second, sampleRate: 44_100, to: secondURL)

    let firstItem = AVPlayerItem(url: firstURL)
    let player = AVPlayer(playerItem: firstItem)
    player.volume = 0
    let listener = MusicListener()
    listener.listen(to: player)
    defer { listener.stop() }
    await wait(upTo: 20) { firstItem.audioMix != nil }
    player.play()
    var heardTheFirst = false
    await wait(upTo: 30) {
        heardTheFirst = listener.reading().bands.lowMids > 0.9
        return heardTheFirst
    }
    #expect(heardTheFirst)

    player.replaceCurrentItem(with: AVPlayerItem(url: secondURL))
    player.play()
    var heardTheSecond = false
    await wait(upTo: 30) {
        let reading = listener.reading()
        if player.currentTime().seconds > 0.5, reading.bandDecibels.mids > reading.bandDecibels.lowMids + 20 {
            heardTheSecond = true
        }
        return heardTheSecond
    }
    #expect(heardTheSecond)
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func aPlayerHandedOverMidSongIsHeardFromThenOn() async throws {
    await waitForAQuietMoment()
    // The person opens the visuals while a song is already playing.
    let folder = try TemporaryFolder()
    let url = folder.file("Long tone.caf")
    let sound = tone(hz: 300, amplitude: 0.5, seconds: 20, sampleRate: rate)
    try writeSoundFile(left: sound, right: sound, sampleRate: rate, to: url)
    let player = AVPlayer(playerItem: AVPlayerItem(url: url))
    player.volume = 0
    player.play()
    await wait(upTo: 20) { player.currentTime().seconds > 0.5 }
    try #require(player.currentTime().seconds > 0.5)

    let listener = MusicListener()
    listener.listen(to: player)
    defer { listener.stop() }
    var heardTheTone = false
    await wait(upTo: 15) {
        heardTheTone = listener.reading().bands.lowMids > 0.9
        return heardTheTone
    }
    #expect(heardTheTone)
    // And the song carries on playing.
    let timeThen = player.currentTime().seconds
    await wait(upTo: 10) { player.currentTime().seconds > timeThen + 0.3 }
    #expect(player.currentTime().seconds > timeThen + 0.3)
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func theAnalyserKeepsItsMemoryWhenThePlayerSeeks() async throws {
    await waitForAQuietMoment()
    // A seek makes the player set its sound up again. The feed must keep the same
    // ring, or the analyser would start afresh and forget the tempo.
    let folder = try TemporaryFolder()
    let url = folder.file("Long tone.caf")
    let sound = tone(hz: 300, amplitude: 0.5, seconds: 20, sampleRate: rate)
    try writeSoundFile(left: sound, right: sound, sampleRate: rate, to: url)
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.volume = 0
    let feed = PlayerFeed(player: player)
    defer { feed.shutDown() }
    await wait(upTo: 20) { item.audioMix != nil }
    player.play()
    await wait(upTo: 20) { feed.ring.sampleRate == rate && feed.ring.totalWritten > 20_000 }
    let ringBefore = feed.ring
    try #require(ringBefore.sampleRate == rate)
    let writtenBefore = ringBefore.totalWritten

    await player.seek(to: CMTime(seconds: 10, preferredTimescale: 600))
    // After the seek, the readings come from the new place in the song.
    await wait(upTo: 20) {
        guard let offset = feed.timeOffset else { return false }
        let newestTime = Double(feed.ring.totalWritten) / rate + offset
        return feed.ring.totalWritten > writtenBefore + 20_000 && newestTime > 10
    }
    #expect(feed.ring === ringBefore)
    let offset = try #require(feed.timeOffset)
    #expect(Double(feed.ring.totalWritten) / rate + offset > 10)
    #expect(abs(Double(feed.heardUpTo) / rate + offset - player.currentTime().seconds) < 0.05)
}

@MainActor
@Test(.enabled(if: macHasSoundOutput, "This computer has no sound output to play through."))
func aSilencedPlayerIsStillHeardManySecondsIn() async throws {
    await waitForAQuietMoment()
    // A player muted with `isMuted` goes quiet to the tap after about four seconds.
    // Turned down to nothing instead, it must still be heard well past that.
    let folder = try TemporaryFolder()
    let url = folder.file("Long tone.caf")
    let sound = tone(hz: 300, amplitude: 0.5, seconds: 12, sampleRate: rate)
    try writeSoundFile(left: sound, right: sound, sampleRate: rate, to: url)
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.volume = 0
    let listener = MusicListener()
    listener.listen(to: player)
    defer { listener.stop() }
    await wait(upTo: 20) { item.audioMix != nil }
    player.play()

    var quietMoments: [Double] = []
    var loudMoments = 0
    await wait(upTo: 40) {
        let reading = listener.reading()
        let time = player.currentTime().seconds
        if time > 5, time < 7.5, player.timeControlStatus == .playing {
            if reading.bandDecibels.lowMids > -12 { loudMoments += 1 } else { quietMoments.append(time) }
        }
        return time > 7.5
    }
    #expect(loudMoments > 20)
    #expect(quietMoments.isEmpty, "quiet at \(quietMoments)")
}
