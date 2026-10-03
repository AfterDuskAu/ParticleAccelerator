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
            MainView(listener: appDelegate.listener) { urls in
                appDelegate.play(urls)
            }
            .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
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

/// The window: for now the library's sound check, which takes a song dropped on it.
private struct MainView: View {
    let listener: MusicListener
    let play: ([URL]) -> Void
    @State private var isDropTarget = false

    var body: some View {
        SoundCheckView(listener: listener)
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
