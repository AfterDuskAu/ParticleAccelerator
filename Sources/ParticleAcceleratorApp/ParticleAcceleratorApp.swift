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
            .frame(minWidth: 760, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { appDelegate.chooseSong() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Playback") {
                Button(appDelegate.listener.isPlaying ? "Pause" : "Play") {
                    appDelegate.playOrPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(appDelegate.listener.songTitle == nil)
                Button(appDelegate.listener.isMuted ? "Unmute" : "Mute") {
                    appDelegate.listener.isMuted.toggle()
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
                if listener.songTitle == nil {
                    VStack(spacing: 6) {
                        Text("Drop a song file here, or choose File → Open…")
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

/// Owns the one listener, and takes song files however they arrive: the Open menu, a
/// drop on the window, or a file opened with the app from the Finder or the Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let listener = MusicListener()

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

    func play(_ urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            try listener.play(songFile: url)
        } catch {
            show(error)
        }
    }

    func chooseSong() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a song to play"
        if panel.runModal() == .OK, let url = panel.url {
            play([url])
        }
    }

    func playOrPause() {
        if listener.isPlaying {
            listener.pause()
        } else {
            do {
                try listener.resume()
            } catch {
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "That song can't be played"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
