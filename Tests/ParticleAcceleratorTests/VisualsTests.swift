import Testing

@testable import ParticleAccelerator

@Test func visualsAreNumberedOneUpWithoutGaps() {
    #expect(Visuals.all.map(\.number) == Array(1...Visuals.all.count))
}

@Test func everyVisualHasAName() {
    #expect(Visuals.all.allSatisfy { !$0.name.isEmpty })
}

@Test func menusShowAVisualByItsNumberOnly() {
    #expect(Visuals.all[0].title == "Visualizer 1")
    #expect(Visuals.all[2].title == "Visualizer 3")
    #expect(Visuals.all[2].name == "Particle Wave")
}
