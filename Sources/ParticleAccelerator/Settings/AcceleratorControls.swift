import AppKit
import SwiftUI

/// The controls panel: everything a person can change about the chosen visual while it
/// plays. Each control is a slider, under the visual's own headings, and each band's
/// colour has a colour picker.
///
///     AcceleratorControls(settings: $settings)
///
/// A change shows in the visual at the next frame. The changes are part of
/// `AcceleratorSettings`, so they're saved wherever the host saves those, and a visual
/// looks the same in any app that's handed the same settings.
public struct AcceleratorControls: View {
    @Binding private var settings: AcceleratorSettings

    public init(settings: Binding<AcceleratorSettings>) {
        _settings = settings
    }

    public var body: some View {
        let controls = StageRenderer.controls(ofVisual: settings.visual)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(controls)
                if controls.isEmpty {
                    Text("Visualizer \(settings.visual) isn't built yet, so there's nothing to change.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Self.groups(of: controls), id: \.name) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name)
                            .font(.headline)
                        ForEach(group.controls) { control in
                            ControlRow(
                                control: control, value: settings.controls.value(of: control),
                                isChanged: settings.controls.isChanged(control),
                                set: { settings.controls.set($0, for: control) },
                                reset: { settings.controls.reset(control) }
                            )
                            // Only the row whose control moved is drawn again, so
                            // dragging one slider doesn't hold the visual up.
                            .equatable()
                        }
                    }
                }
                if !controls.isEmpty {
                    colours
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
    }

    private func header(_ controls: [VisualControl]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // Every visual with something to show, to choose between.
                Picker("Visualizer", selection: $settings.visual) {
                    ForEach(Visuals.all.filter { $0.canBeShown || $0.number == settings.visual }) { visual in
                        Text(visual.title).tag(visual.number)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Reset All") {
                    settings.controls.reset(controls)
                }
                .disabled(!settings.controls.hasChanges(among: controls))
                .help("Put every control and colour back to the visual's own")
            }
            Text("Changes show straight away and are kept. Rest the pointer on a control to see what it does.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var colours: some View {
        let changing = BandPalette.changesControl
        let changes = settings.controls.value(of: changing) >= 0.5
        return VStack(alignment: .leading, spacing: 8) {
            Text("Colours")
                .font(.headline)
            Toggle(
                changing.name,
                isOn: Binding(
                    get: { changes },
                    set: { isOn in
                        if isOn {
                            settings.controls.set(1, for: changing)
                        } else {
                            settings.controls.reset(changing)
                        }
                    })
            )
            .help(changing.help)
            if changes {
                let seconds = BandPalette.secondsControl
                ControlRow(
                    control: seconds, value: settings.controls.value(of: seconds),
                    isChanged: settings.controls.isChanged(seconds),
                    set: { settings.controls.set($0, for: seconds) },
                    reset: { settings.controls.reset(seconds) }
                )
                .equatable()
            }
            Group {
                ForEach(Band.allCases, id: \.self) { band in
                    ColourRow(
                        band: band, colour: settings.controls.colour(of: band),
                        isChanged: settings.controls.isColourChanged(band),
                        set: { settings.controls.setColour($0, for: band) },
                        reset: { settings.controls.resetColour(of: band) }
                    )
                    .equatable()
                }
            }
            // A person's own colours wait while the colours are choosing themselves.
            .disabled(changes)
            .opacity(changes ? 0.35 : 1)
            Text(
                changes
                    ? "The colours are choosing themselves. Switch that off to pick your own."
                    : "The sound check's bars and meters use the same colours."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The controls under their headings, in the order the visual lists them.
    static func groups(of controls: [VisualControl]) -> [(name: String, controls: [VisualControl])] {
        var groups: [(name: String, controls: [VisualControl])] = []
        for control in controls {
            if let index = groups.firstIndex(where: { $0.name == control.group }) {
                groups[index].controls.append(control)
            } else {
                groups.append((control.group, [control]))
            }
        }
        return groups
    }
}

/// One control: its name, its value in words, a way back to the visual's own setting,
/// and the slider.
private struct ControlRow: View, Equatable {
    let control: VisualControl
    let value: Float
    let isChanged: Bool
    let set: (Float) -> Void
    let reset: () -> Void

    /// Two rows are the same when they show the same thing; what they do when moved
    /// doesn't come into it.
    static func == (one: ControlRow, other: ControlRow) -> Bool {
        one.control == other.control && one.value == other.value && one.isChanged == other.isChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(control.name)
                Spacer()
                Text(control.text(for: value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                ResetButton(
                    isChanged: isChanged, name: control.name,
                    help: "Back to \(control.text(for: control.usual))", reset: reset)
            }
            Slider(
                value: Binding(
                    get: { control.sliderPlace(of: value) },
                    set: { set(control.value(atSliderPlace: $0)) }),
                in: 0...1
            )
            .controlSize(.small)
            .accessibilityLabel("\(control.group): \(control.name)")
            .accessibilityValue(control.text(for: value))
        }
        .help(control.help)
    }
}

/// One band's colour: a colour picker, and a way back to the band's own colour.
private struct ColourRow: View, Equatable {
    let band: Band
    let colour: SIMD3<Float>
    let isChanged: Bool
    let set: (SIMD3<Float>) -> Void
    let reset: () -> Void

    static func == (one: ColourRow, other: ColourRow) -> Bool {
        one.band == other.band && one.colour == other.colour && one.isChanged == other.isChanged
    }

    var body: some View {
        HStack(spacing: 6) {
            ColorPicker(
                "\(band.name) (\(SoundCheckView.pitches(of: band)))",
                selection: Binding(
                    get: { Color(.sRGB, red: Double(colour.x), green: Double(colour.y), blue: Double(colour.z)) },
                    set: { picked in
                        // The colour panel can hand back a colour in any colour space.
                        guard let shown = NSColor(picked).usingColorSpace(.sRGB) else { return }
                        set(SIMD3(Float(shown.redComponent), Float(shown.greenComponent), Float(shown.blueComponent)))
                    }),
                supportsOpacity: false)
            ResetButton(
                isChanged: isChanged, name: "\(band.name) colour", help: "Back to the band's own colour",
                reset: reset)
        }
    }
}

/// A small "put it back" arrow. It keeps its place when there's nothing to put back, so
/// the row doesn't jump about.
private struct ResetButton: View {
    let isChanged: Bool
    let name: String
    let help: String
    let reset: () -> Void

    var body: some View {
        Button(action: reset) {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .opacity(isChanged ? 1 : 0)
        .disabled(!isChanged)
        .help(help)
        .accessibilityLabel("Reset \(name)")
    }
}
