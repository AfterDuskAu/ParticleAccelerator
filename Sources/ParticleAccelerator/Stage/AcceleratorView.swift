import SwiftUI

/// The visuals: the chosen visual, moving to whatever the listener hears.
///
///     AcceleratorView(listener: listener, settings: settings)
///
/// It fills the space it's given, and stops drawing when its window can't be seen.
public struct AcceleratorView: View {
    private let listener: MusicListener
    private let settings: AcceleratorSettings
    @State private var status = StageStatus()

    public init(listener: MusicListener, settings: AcceleratorSettings = AcceleratorSettings()) {
        self.listener = listener
        self.settings = settings
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            StageRepresentable(listener: listener, settings: settings, status: status)
            if let problem = status.problem {
                Text(problem)
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if settings.showsFrameTime, let frameTime = status.frameTime {
                Text(frameTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                    .padding(10)
                    .accessibilityLabel("Frame time")
                    .accessibilityValue(frameTime)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
