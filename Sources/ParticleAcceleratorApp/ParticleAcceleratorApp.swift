import AVFoundation
import AppKit
import ParticleAccelerator
import SwiftUI

/// The stand-alone app. It stays a thin shell over the library: anything it can do, an
/// app that uses the library (Music Organizer) can do too. All it adds is the window,
/// the menus and the ways to hand it a song file.
@main
struct ParticleAcceleratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Started with `swift run` there's no .app bundle, so say it's a normal app with
        // a window and a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("Particle Accelerator", id: "main") {
            MainView(listener: appDelegate.listener, choices: appDelegate.choices) { urls in
                appDelegate.play(urls)
            }
        }
        .commands {
            // These go in the View menu, above Enter Full Screen.
            CommandGroup(before: .toolbar) {
                let choices = appDelegate.choices
                Toggle("Sound Check", isOn: Binding(
                    get: { choices.showsSoundCheck }, set: { choices.showsSoundCheck = $0 }))
                    .keyboardShortcut("d")
                Toggle("Controls", isOn: Binding(
                    get: { choices.showsControls }, set: { choices.showsControls = $0 }))
                    .keyboardShortcut("e")
                Toggle("Frame Time", isOn: Binding(
                    get: { choices.basics.showsFrameTime },
                    set: { choices.basics.showsFrameTime = $0 }))
                    .keyboardShortcut("t")
                Picker("Visualizer", selection: Binding(
                    get: { choices.basics.visual }, set: { choices.basics.visual = $0 })
                ) {
                    ForEach(Visuals.all.filter(\.canBeShown)) { visual in
                        Text(visual.title).tag(visual.number)
                    }
                }
                Picker("Quality", selection: Binding(
                    get: { choices.basics.quality }, set: { choices.basics.quality = $0 })
                ) {
                    Text("Auto").tag(Quality.auto)
                    Divider()
                    Text("Low").tag(Quality.low)
                    Text("Medium").tag(Quality.medium)
                    Text("High").tag(Quality.high)
                    Text("Ultra").tag(Quality.ultra)
                }
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") { appDelegate.chooseSong(asHost: false) }
                    .keyboardShortcut("o")
            }
            CommandMenu("Listen") {
                let source = appDelegate.listener.source
                Button("Song File…") { appDelegate.chooseSong(asHost: false) }
                Toggle("This Mac's Sound", isOn: Binding(
                    get: { source == .thisMac },
                    set: { $0 ? appDelegate.listenToThisMac() : appDelegate.stopListening() }))
                    .keyboardShortcut("1")
                Toggle("Microphone", isOn: Binding(
                    get: { source == .microphone },
                    set: { $0 ? appDelegate.listenToMicrophone() : appDelegate.stopListening() }))
                    .keyboardShortcut("2")
                Divider()
                // The way a host app such as Music Organizer plays a song: in a player of
                // its own, which it hands to the listener. For checking that path.
                Button("Song File, the Way a Host App Plays It…") {
                    appDelegate.chooseSong(asHost: true)
                }
                Divider()
                Button("Stop Listening") { appDelegate.stopListening() }
                    .keyboardShortcut(".")
                    .disabled(source == .nothing)
            }
            CommandMenu("Playback") {
                let source = appDelegate.listener.source
                Button(appDelegate.listener.isPlaying ? "Pause" : "Play") {
                    appDelegate.playOrPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(source != .songFile && source != .player)
                Button(appDelegate.listener.isMuted ? "Unmute" : "Mute") {
                    appDelegate.toggleMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

/// What the person has chosen in the app. The settings are saved in the app's own
/// preferences, and read back the next time it opens.
@MainActor
@Observable
final class Choices {
    private static let settingsKey = "AcceleratorSettings"
    private static let soundCheckKey = "ShowsSoundCheck"
    private static let controlsKey = "ShowsControls"

    /// The settings, in two parts that are watched separately. The menus only read the
    /// first, so they aren't rebuilt for every step of a slider being dragged: that
    /// took the app's whole main thread (measured 2026-10-03).
    ///
    /// `basics` is everything but the person's changes to the controls, and `controls`
    /// is those changes.
    var basics: AcceleratorSettings {
        didSet { if basics != oldValue { save() } }
    }
    var controls: ControlValues {
        didSet { if controls != oldValue { save() } }
    }

    /// Both parts together, as the library takes them.
    var settings: AcceleratorSettings {
        get {
            var whole = basics
            whole.controls = controls
            return whole
        }
        set {
            var newBasics = newValue
            newBasics.controls = ControlValues()
            // Only what has changed is set, so only the views that read it are redrawn.
            if newBasics != basics { basics = newBasics }
            if newValue.controls != controls { controls = newValue.controls }
        }
    }

    private func save() {
        guard let saved = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(saved, forKey: Self.settingsKey)
    }

    /// Shows the plain bars and meters under the visual.
    var showsSoundCheck: Bool {
        didSet { UserDefaults.standard.set(showsSoundCheck, forKey: Self.soundCheckKey) }
    }
    /// Shows the controls panel beside the visual.
    var showsControls: Bool {
        didSet { UserDefaults.standard.set(showsControls, forKey: Self.controlsKey) }
    }

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.settingsKey)
        var whole = saved.flatMap { try? JSONDecoder().decode(AcceleratorSettings.self, from: $0) }
            ?? AcceleratorSettings()
        controls = whole.controls
        whole.controls = ControlValues()
        basics = whole
        showsSoundCheck = UserDefaults.standard.bool(forKey: Self.soundCheckKey)
        showsControls = UserDefaults.standard.bool(forKey: Self.controlsKey)
    }
}

/// The window: the visual, with the sound check under it and the controls beside it
/// when they're asked for. A song can be dropped anywhere on it.
private struct MainView: View {
    let listener: MusicListener
    let choices: Choices
    let play: ([URL]) -> Void
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 1) {
            VStack(spacing: 1) {
                AcceleratorView(listener: listener, settings: choices.settings)
                    .frame(minWidth: 560, minHeight: 260)
                if choices.showsSoundCheck {
                    // The bars sit under the visual in the same order and the same
                    // colours as its sections, so one reads against the other.
                    SoundCheckView(listener: listener, settings: choices.settings)
                        .frame(height: 370)
                }
            }
            if choices.showsControls {
                AcceleratorControls(
                    settings: Binding(get: { choices.settings }, set: { choices.settings = $0 })
                )
                .frame(width: 320)
            }
        }
        .background(Color(white: 0.2))
        .frame(
            minWidth: choices.showsControls ? 1_110 : 820,
            minHeight: choices.showsSoundCheck ? 660 : 520
        )
        .overlay(alignment: .top) {
            if listener.source == .nothing {
                VStack(spacing: 6) {
                    Text("Drop a song file here, or choose from the Listen menu")
                        .font(.title3)
                    Text("Particle Accelerator \(Accelerator.version)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 110)
                .environment(\.colorScheme, .dark)
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            play(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTarget = $0 }
    }
}

/// Owns the one listener, and takes song files however they arrive: the menus, a drop
/// on the window, or a file opened with the app from the Finder or the Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let listener = MusicListener()
    let choices = Choices()
    /// When the app plays a song the way a host app would, this is its player.
    private var hostPlayer: AVPlayer?
    /// `--as-host`: song files handed to the app are played the way a host app would.
    private let playsAsHost = CommandLine.arguments.contains("--as-host")

    override init() {
        super.init()
        // `--muted` starts with the speakers silenced, for checking the visuals without
        // playing sound at anyone:
        //     open "build/Particle Accelerator.app" --args --muted
        if CommandLine.arguments.contains("--muted") {
            listener.isMuted = true
        }

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The window is the app: closing it stops the music and quits.
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        play(urls)
    }

    // MARK: What to listen to

    func play(_ urls: [URL]) {
        guard let url = urls.first else { return }
        if playsAsHost {
            playAsHost(url)
            return
        }
        letGoOfHostPlayer()
        do {
            try listener.play(songFile: url)
        } catch {
            show(error)
        }
    }

    func chooseSong(asHost: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a song to play"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if asHost {
            playAsHost(url)
        } else {
            letGoOfHostPlayer()
            do {
                try listener.play(songFile: url)
            } catch {
                show(error)
            }
        }
    }

    func listenToThisMac() {
        letGoOfHostPlayer()
        do {
            try listener.listenToThisMac()
        } catch {
            show(error)
        }
    }

    func listenToMicrophone() {
        letGoOfHostPlayer()
        Task {
            do {
                try await listener.listenToMicrophone()
            } catch {
                show(error)
            }
        }
    }

    func stopListening() {
        letGoOfHostPlayer()
        listener.stop()
    }

    private func letGoOfHostPlayer() {
        hostPlayer?.pause()
        hostPlayer = nil
    }

    /// Plays a song the way Music Organizer plays one from YouTube: in an `AVPlayer`,
    /// as a "joined composition" (the sound is one stream, joined to the picture, which
    /// is another). The player is handed to the listener, as a host would hand its own.
    private func playAsHost(_ url: URL) {
        Task {
            do {
                let asset = AVURLAsset(url: url)
                guard let sound = try await asset.loadTracks(withMediaType: .audio).first else {
                    throw HostProblem(message: "“\(url.lastPathComponent)” has no sound in it.")
                }
                let joined = AVMutableComposition()
                let track = joined.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                try track?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: try await asset.load(.duration)),
                    of: sound, at: .zero)

                let player = AVPlayer(playerItem: AVPlayerItem(asset: joined))
                // Turned down, not muted: macOS stops handing a muted player's sound
                // to the listener after a few seconds.
                player.volume = listener.isMuted ? 0 : 1
                hostPlayer?.pause()
                hostPlayer = player
                listener.listen(to: player)
                player.play()
            } catch {
                show(error)
            }
        }
    }

    // MARK: Playback

    func playOrPause() {
        if let hostPlayer {
            if hostPlayer.timeControlStatus == .paused { hostPlayer.play() } else { hostPlayer.pause() }
        } else if listener.isPlaying {
            listener.pause()
        } else {
            do {
                try listener.resume()
            } catch {
                show(error)
            }
        }
    }

    func toggleMute() {
        listener.isMuted.toggle()
        hostPlayer?.volume = listener.isMuted ? 0 : 1
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "That can't be listened to"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

/// Something that went wrong while the app was playing a song as a host would.
private struct HostProblem: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
