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
///
/// Each visual has a standard, and can be locked (the owner, 2026-10-04):
/// - **Lock** keeps the visual as it is: nothing in the panel can be moved until it's
///   unlocked.
/// - **Set Standard** makes the settings as they are now the visual's standard.
/// - **Reset to Standard** goes back to that standard.
/// - **Reset All** goes back to the visual's base: its plain first settings.
public struct AcceleratorControls: View {
    @Binding private var settings: AcceleratorSettings
    @State private var isAskingToSetStandard = false

    public init(settings: Binding<AcceleratorSettings>) {
        _settings = settings
    }

    public var body: some View {
        let visual = settings.visual
        let controls = StageRenderer.controls(ofVisual: visual)
        let isLocked = settings.controls.isLocked(visual: visual)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(hasControls: !controls.isEmpty, isLocked: isLocked)
                if controls.isEmpty {
                    Text("Visualizer \(visual) isn't built yet, so there's nothing to change.")
                        .foregroundStyle(.secondary)
                }
                Group {
                    ForEach(Self.groups(of: controls), id: \.name) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.name)
                                .font(.headline)
                            ForEach(group.controls) { control in
                                row(for: control)
                            }
                        }
                    }
                    if !controls.isEmpty {
                        colours(ofVisual: visual)
                    }
                }
                .disabled(isLocked)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
        .confirmationDialog(
            "Make these settings Visualizer \(visual)'s standard?", isPresented: $isAskingToSetStandard
        ) {
            Button("Set Standard") { settings.controls.setStandard(visual: visual) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reset to Standard will come back to these from now on. The standard it has now is replaced.")
        }
    }

    private func row(for control: VisualControl) -> some View {
        ControlRow(
            control: control, value: settings.controls.value(of: control),
            standard: settings.controls.standard(of: control),
            isChanged: settings.controls.isChanged(control),
            set: { settings.controls.set($0, for: control) },
            reset: { settings.controls.reset(control) }
        )
        // Only the row whose control moved is drawn again, so dragging one slider
        // doesn't hold the visual up.
        .equatable()
    }

    private func header(hasControls: Bool, isLocked: Bool) -> some View {
        let visual = settings.visual
        let differsFromStandard = settings.controls.differsFromStandard(visual: visual)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // Every visual with something to show, to choose between.
                Picker("Visualizer", selection: $settings.visual) {
                    ForEach(Visuals.all.filter { $0.canBeShown || $0.number == visual }) { visual in
                        Text(visual.title).tag(visual.number)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                if hasControls {
                    // The padlock shows how it is now; the word says what a click does.
                    Button {
                        settings.controls.setLocked(!isLocked, visual: visual)
                    } label: {
                        Label(isLocked ? "Unlock" : "Lock", systemImage: isLocked ? "lock.fill" : "lock.open")
                    }
                    .help(
                        isLocked
                            ? "Let this visual's controls be changed again"
                            : "Keep this visual as it is: nothing here can be moved until it's unlocked")
                }
            }
            if hasControls {
                HStack(spacing: 6) {
                    Button("Set Standard") { isAskingToSetStandard = true }
                        .disabled(isLocked || !differsFromStandard)
                        .help("Make the settings as they are now this visual's standard")
                    Button("Reset to Standard") { settings.controls.resetToStandard(visual: visual) }
                        .disabled(isLocked || !differsFromStandard)
                        .help("Put every control and colour back to this visual's standard")
                    Button("Reset All") { settings.controls.resetToBase(visual: visual) }
                        .disabled(isLocked || !settings.controls.differsFromBase(visual: visual))
                        .help("Put every control and colour back to the visual's base: its plain first settings")
                }
                .controlSize(.small)
                Text(
                    isLocked
                        ? "Locked, so nothing is changed by accident. Unlock to change it."
                        : differsFromStandard
                            ? "Changed from its standard. Changes show straight away and are kept."
                            : "At its standard. Changes show straight away and are kept. Rest the pointer on a control to see what it does."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func colours(ofVisual visual: Int) -> some View {
        let changing = BandPalette.changesControl(ofVisual: visual)
        let changes = settings.controls.value(of: changing) >= 0.5
        return VStack(alignment: .leading, spacing: 8) {
            Text("Colours")
                .font(.headline)
            Toggle(
                changing.name,
                isOn: Binding(
                    get: { changes },
                    set: { settings.controls.set($0 ? 1 : 0, for: changing) })
            )
            .help(changing.help)
            if changes {
                row(for: BandPalette.secondsControl(ofVisual: visual))
            }
            Group {
                ForEach(Band.allCases, id: \.self) { band in
                    ColourRow(
                        band: band, colour: settings.controls.colour(of: band, in: visual),
                        isChanged: settings.controls.isColourChanged(band, in: visual),
                        set: { settings.controls.setColour($0, for: band, in: visual) },
                        reset: { settings.controls.resetColour(of: band, in: visual) }
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
                    : "These are this visual's colours. The sound check's bars and meters show them too."
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

/// One control: its name, its value in words, a way back to its standard, and the
/// slider.
private struct ControlRow: View, Equatable {
    let control: VisualControl
    let value: Float
    let standard: Float
    let isChanged: Bool
    let set: (Float) -> Void
    let reset: () -> Void

    /// Two rows are the same when they show the same thing; what they do when moved
    /// doesn't come into it.
    static func == (one: ControlRow, other: ControlRow) -> Bool {
        one.control == other.control && one.value == other.value && one.standard == other.standard
            && one.isChanged == other.isChanged
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
                    help: "Back to its standard, \(control.text(for: standard))", reset: reset)
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

/// One band's colour: a colour picker, and a way back to its standard colour.
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
                isChanged: isChanged, name: "\(band.name) colour", help: "Back to its standard colour",
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
