import Testing

@testable import ParticleAccelerator

@Test func visualsAreNumberedOneUpWithoutGaps() {
    #expect(Visuals.all.map(\.number) == Array(1...Visuals.all.count))
}

@Test func everyVisualHasAName() {
    #expect(Visuals.all.allSatisfy { !$0.name.isEmpty })
}

@Test func aTitleIsTheNumberAndTheName() {
    #expect(Visuals.all[0].title == "1 · Ring & Ink")
}
