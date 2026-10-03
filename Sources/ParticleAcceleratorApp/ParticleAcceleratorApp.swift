import AppKit
import ParticleAccelerator
import SwiftUI

/// The stand-alone app. It stays a thin shell over the library: anything it can do, an
/// app that uses the library (Music Organizer) can do too.
@main
struct ParticleAcceleratorApp: App {
    init() {
        // Started with `swift run` there's no .app bundle, so say it's a normal app with
        // a window and a Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Particle Accelerator") {
            WelcomeView()
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}

/// What the first build shows: nothing plays yet, and the visuals on their way.
private struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 18) {
            Text("Particle Accelerator")
                .font(.system(size: 34, weight: .bold))
            Text("Visuals that move with the music. Nothing plays yet: this is the first build.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Visuals.all) { visual in
                    HStack {
                        Text(visual.title)
                        Spacer()
                        Text(visual.isBuilt ? "Ready" : "Coming")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 280)
            .padding(.top, 8)
            Text("Version \(Accelerator.version)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
