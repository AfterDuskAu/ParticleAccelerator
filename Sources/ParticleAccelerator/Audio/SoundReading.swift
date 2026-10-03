/// One of the six named parts of the sound, from the deepest bass to the highest sparkle.
enum Band: Int, CaseIterable {
    case sub, kick, lowMids, mids, vocals, air

    /// The pitches the band covers, in Hz.
    var frequencies: Range<Float> {
        switch self {
        case .sub: return 20..<60
        case .kick: return 60..<150
        case .lowMids: return 150..<500
        case .mids: return 500..<2_000
        case .vocals: return 2_000..<6_000
        case .air: return 6_000..<16_000
        }
    }

    var name: String {
        switch self {
        case .sub: return "Sub"
        case .kick: return "Kick"
        case .lowMids: return "Low mids"
        case .mids: return "Mids"
        case .vocals: return "Vocals and snare"
        case .air: return "Air"
        }
    }
}

/// One number for each of the six bands.
struct BandValues: Equatable {
    var sub: Float = 0
    var kick: Float = 0
    var lowMids: Float = 0
    var mids: Float = 0
    var vocals: Float = 0
    var air: Float = 0

    subscript(band: Band) -> Float {
        get {
            switch band {
            case .sub: return sub
            case .kick: return kick
            case .lowMids: return lowMids
            case .mids: return mids
            case .vocals: return vocals
            case .air: return air
            }
        }
        set {
            switch band {
            case .sub: sub = newValue
            case .kick: kick = newValue
            case .lowMids: lowMids = newValue
            case .mids: mids = newValue
            case .vocals: vocals = newValue
            case .air: air = newValue
            }
        }
    }
}

/// What the music is doing right now: everything a visual can move to.
///
/// "Levels" run from 0 to 1 and are auto-gained: 1 is the loudest that part of the sound
/// has been in the last ten seconds or so, and 0 is far quieter than that (or silence).
/// So a quiet song and a loud one both move, and a quiet verse looks different from a
/// big drop.
struct SoundReading: Equatable {
    /// How loud silence is said to be, in decibels. Nothing reads lower.
    static let silenceDecibels: Float = -120

    /// The spectrum as 64 levels, bass on the left (30 Hz) to highs on the right (16 kHz).
    var bars = SIMD64<Float>(repeating: 0)

    /// The level of each named band.
    var bands = BandValues()
    /// How loud each band really is, in decibels below full volume, before auto-gain.
    var bandDecibels = BandValues(
        sub: silenceDecibels, kick: silenceDecibels, lowMids: silenceDecibels,
        mids: silenceDecibels, vocals: silenceDecibels, air: silenceDecibels)

    /// The level of the whole sound.
    var loudness: Float = 0
    /// How loud the whole sound really is, in decibels below full volume, before auto-gain.
    var loudnessDecibels: Float = silenceDecibels

    /// A pulse on each beat heard: 1 as the kick lands, fading to 0 within about a fifth
    /// of a second.
    var beat: Float = 0
    /// How many beats have been heard so far, so a visual can tell a new one has landed.
    var beatsHeard = 0

    /// The song's tempo, or nil while it isn't clear.
    var beatsPerMinute: Double?
    /// How far through the current beat the music is, from 0 up to 1, on the tempo's
    /// steady count. It keeps counting through a bar where the drums drop out.
    var beatPhase: Double = 0
    /// How many beats the steady count has reached, for things that step once a beat.
    var steadyBeats = 0

    /// How many seconds of sound have been measured.
    var seconds: Double = 0

    /// A reading of silence.
    static let silence = SoundReading()

    /// The same reading with the sound gone quiet: the tempo and the beat counts are
    /// kept, so a visual settles down but doesn't lose its place.
    var quieted: SoundReading {
        var quiet = SoundReading.silence
        quiet.beatsHeard = beatsHeard
        quiet.beatsPerMinute = beatsPerMinute
        quiet.beatPhase = beatPhase
        quiet.steadyBeats = steadyBeats
        quiet.seconds = seconds
        return quiet
    }
}
