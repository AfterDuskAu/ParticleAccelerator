import AVFoundation
import CoreAudio

/// Hears a microphone or line input: a room, a turntable, a band. It listens to
/// whichever input is chosen in System Settings → Sound → Input, and follows it if
/// that changes.
///
/// One exception: a Bluetooth headset. Listening to its microphone makes macOS switch
/// the headset to call quality, which spoils the music the person is hearing through
/// it. So when the chosen input is a Bluetooth headset, this uses the Mac's own
/// microphone instead and says so.
final class MicrophoneFeed: SoundFeed {
    /// The input's name, such as "iMac Microphone".
    private(set) var inputName: String
    /// Something the person should know about which input is being used, or nil.
    private(set) var note: String?
    /// Called after the person chooses a different input and the feed has moved to it,
    /// or has had to stop.
    var onInputChanged: (() -> Void)?
    private var listening: DeviceListening
    private var inputWatcher: DeviceWatcher?
    private var isShutDown = false

    var ring: SampleRing { listening.ring }
    /// The room has already heard the sound by the time the microphone has, so there's
    /// nothing to wait for.
    var heardUpTo: Int64 { ring.totalWritten }
    var isHeldStill: Bool { false }

    /// Asks the person, the first time, whether this app may use the microphone.
    /// Returns whether it may.
    static func askPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Which input would be listened to right now. Throws, in plain English, if there
    /// isn't one that can be. It starts nothing, so it's safe to call before asking
    /// for permission.
    static func chooseInput() throws -> InputChoice {
        let chosen = SoundDevices.defaultInput
        let builtIn = SoundDevices.builtInMicrophone
        return try choose(
            chosen: chosen.map { ($0, SoundDevices.name(of: $0) ?? "the chosen input", SoundDevices.isBluetooth($0)) },
            builtIn: builtIn.map { ($0, SoundDevices.name(of: $0) ?? "this Mac's microphone") })
    }

    struct InputChoice: Equatable {
        var device: AudioDeviceID
        var name: String
        var note: String?
    }

    /// The rule for which input to use, kept apart from Core Audio so it can be tested.
    static func choose(
        chosen: (device: AudioDeviceID, name: String, isBluetooth: Bool)?,
        builtIn: (device: AudioDeviceID, name: String)?
    ) throws -> InputChoice {
        guard let chosen else {
            throw ListeningProblem(
                message: "This Mac has no microphone or line input to listen to. Check System Settings → Sound → Input.")
        }
        guard chosen.isBluetooth else {
            return InputChoice(device: chosen.device, name: chosen.name, note: nil)
        }
        guard let builtIn else {
            throw ListeningProblem(
                message: "The Mac's sound input is “\(chosen.name)”, a Bluetooth headset. Listening to it would switch the headset to call quality and spoil what you're hearing. Choose another input in System Settings → Sound → Input, then try again.")
        }
        return InputChoice(
            device: builtIn.device, name: builtIn.name,
            note: "Listening to \(builtIn.name). The Mac's chosen input, “\(chosen.name)”, is a Bluetooth headset, and listening to it would switch it to call quality.")
    }

    /// Call `askPermission` first: without permission macOS hands over silence.
    init() throws {
        let choice = try Self.chooseInput()
        listening = try Self.listen(to: choice)
        inputName = choice.name
        note = choice.note
        inputWatcher = SoundDevices.watchDefaultDevice(input: true) { [weak self] in
            self?.startAgain()
        }
    }

    func shutDown() {
        isShutDown = true
        inputWatcher = nil
        listening.stop()
    }

    /// The person chose a different input: move to it.
    private func startAgain() {
        guard !isShutDown else { return }
        do {
            let choice = try Self.chooseInput()
            let newListening = try Self.listen(to: choice)
            listening.stop()
            listening = newListening
            inputName = choice.name
            note = choice.note
        } catch {
            // Carry on with the input already in use, and say what went wrong.
            note = error.localizedDescription
        }
        onInputChanged?()
    }

    private static func listen(to choice: InputChoice) throws -> DeviceListening {
        guard let rate = SoundDevices.sampleRate(of: choice.device) else {
            throw ListeningProblem(message: "“\(choice.name)” can't be listened to: it doesn't say how fast its sound runs.")
        }
        let listening = DeviceListening(device: choice.device, sampleRate: rate)
        guard listening.start() else {
            throw ListeningProblem(message: "“\(choice.name)” can't be listened to: Core Audio wouldn't start it.")
        }
        return listening
    }
}
