import Foundation
import Testing
import ScrobbleCore
import TestSupport
@testable import ShazamLibrary

@Suite(.serialized) struct ShazamLibraryTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let noShazamApp = URL(fileURLWithPath: "/nonexistent/Shazam.app")

    @Test func notInstalledWhenNoContainerAndNoApp() throws {
        let f = try ShazamFixture(createContainer: false); defer { f.remove() }
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)
        #expect(lib.read(since: .distantPast, recentLimit: 20).status == .notInstalled)
    }

    @Test func noLibraryYetWhenAppInstalledButNoContainer() throws {
        let f = try ShazamFixture(createContainer: false); defer { f.remove() }
        let fakeApp = FileManager.default.temporaryDirectory
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: fakeApp)
        #expect(lib.read(since: .distantPast, recentLimit: 20).status == .noLibraryYet)
    }

    @Test func noLibraryYetWhenDatabaseMissingOrEmpty() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)
        #expect(lib.read(since: .distantPast, recentLimit: 20).status == .noLibraryYet)
        try f.createDatabase()
        #expect(lib.read(since: .distantPast, recentLimit: 20).status == .noLibraryYet)
    }

    @Test func readsTagsSinceAscendingAndRecentDescending() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        try f.addTag(title: "One", artists: ["A"], album: "Al", date: t0)
        try f.addTag(title: "Two", artists: ["B"], album: nil, date: t0 + 60)
        try f.addTag(title: "Three", artists: ["C"], album: "Cl", date: t0 + 120)
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)
        let r = lib.read(since: t0, recentLimit: 2)
        #expect(r.status == .ok)
        #expect(r.tagsSince.map(\.track.title) == ["Two", "Three"])
        #expect(r.recent.map(\.track.title) == ["Three", "Two"])
        #expect(r.tagsSince.first?.track.album == nil)            // Review Focus 2: no album still read
        #expect(r.tagsSince.last?.date == t0 + 120)
    }

    @Test func multipleArtistsUseFirstAndMissingArtistIsSkipped() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        try f.addTag(title: "Feat", artists: ["Main", "Guest"], album: nil, date: t0)
        try f.addTag(title: "NoArtist", artists: [], album: nil, date: t0 + 1)
        try f.addTag(title: nil, artists: ["X"], album: nil, date: t0 + 2)
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.tagsSince.map(\.track) == [Track(artist: "Main", title: "Feat")])
    }

    @Test func unsupportedSchemaNamesTheMissingColumn() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase(dropColumn: "ZNAME")
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.status == .unsupportedSchema("ZSHARTISTMO.ZNAME"))
    }

    @Test func unreadableDatabaseIsAccessDenied() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase(wal: false)
        try f.addTag(title: "One", artists: ["A"], album: nil, date: t0)
        chmod(f.dbURL.path, 0); defer { chmod(f.dbURL.path, 0o644) }
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.status == .accessDenied)
    }

    @Test func seesRowsStillOnlyInTheWAL() throws {   // the #41 situation
        let f = try ShazamFixture(); defer { f.remove() }
        let writer = try f.createDatabase(wal: true)
        try writer.execute("PRAGMA wal_autocheckpoint=0")
        try f.addTag(title: "Fresh", artists: ["W"], album: nil, date: t0)
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.recent.first?.track.title == "Fresh")
    }

    @Test func looksUpByPK() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        let pk = try f.addTag(title: "One", artists: ["A"], album: nil, date: t0)
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)
        #expect(try lib.tags(withPKs: [pk, 999])[pk]?.track.title == "One")
        #expect(try lib.tags(withPKs: [pk, 999])[999] == nil)
        #expect(try lib.tags(withPKs: []).isEmpty)
    }

    @Test func lookupThrowsWhenDatabaseUnreadable() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        let pk = try f.addTag(title: "One", artists: ["A"], album: nil, date: t0)
        chmod(f.dbURL.path, 0); defer { chmod(f.dbURL.path, 0o644) }
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)
        #expect(throws: (any Error).self) { try lib.tags(withPKs: [pk]) }
    }

    @Test func readsStayFastOnLargeUnindexedLibrary() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        try f.addBulk(count: 15_000, metadataPerTag: 6, start: t0)
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)

        let t1 = ContinuousClock.now
        let all = lib.read(since: .distantPast, recentLimit: 20)   // `since` hits the 5000 cap
        let d1 = ContinuousClock.now - t1
        #expect(all.status == .ok)
        #expect(all.recent.count == 20)
        #expect(all.recent.first?.track.title == "Title 14999")
        #expect(all.tagsSince.count == 5000)
        #expect(all.tagsSince.first?.track.album == "v0")
        #expect(d1 < .milliseconds(1500))

        let t2 = ContinuousClock.now
        let recentOnly = lib.read(since: t0 + 20_000, recentLimit: 20)
        let d2 = ContinuousClock.now - t2
        #expect(recentOnly.recent.count == 20)
        #expect(recentOnly.tagsSince.isEmpty)
        #expect(d2 < .milliseconds(300))
    }

    @Test func firstNonEmptyArtistWinsAndNoLibraryYetOnlyWhenNoRows() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        try f.addTag(title: "Mixed", artists: ["", "B"], album: nil, date: t0)
        let lib = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp)
        #expect(lib.read(since: .distantPast, recentLimit: 20).recent.first?.track.artist == "B")

        let g = try ShazamFixture(); defer { g.remove() }
        try g.createDatabase()
        try g.addTag(title: "NoArtist", artists: [], album: nil, date: t0)
        let r = ShazamLibrary(containerURL: g.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.status == .ok)
        #expect(r.recent.isEmpty)
    }

    @Test func recentSkipsArtistlessRowsAndStillFillsTheLimit() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        for i in 0..<5 { try f.addTag(title: "Ok\(i)", artists: ["A"], album: nil, date: t0 + Double(i)) }
        try f.addTag(title: "Blank", artists: [""], album: nil, date: t0 + 10)
        try f.addTag(title: "None", artists: [], album: nil, date: t0 + 11)
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantFuture, recentLimit: 3)
        #expect(r.recent.map(\.track.title) == ["Ok4", "Ok3", "Ok2"])
    }

    @Test func malformedDatesAreIgnored() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase()
        try f.addTag(title: "Inf", artist: "A", rawSeconds: .infinity)
        try f.addTag(title: "Negative", artist: "A", rawSeconds: -5)
        try f.addTag(title: "Huge", artist: "A", rawSeconds: 1e15)
        try f.addTag(title: "Good", artist: "A", rawSeconds: 700_000_000)
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.status == .ok)
        #expect(r.recent.map(\.track.title) == ["Good"])
        #expect(r.tagsSince.map(\.track.title) == ["Good"])
    }

    @Test func symlinkedDatabaseIsRefused() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase(wal: false)
        try f.addTag(title: "One", artists: ["A"], album: nil, date: t0)
        let real = f.dbURL.deletingLastPathComponent().appendingPathComponent("real.sqlite")
        try FileManager.default.moveItem(at: f.dbURL, to: real)
        try FileManager.default.createSymbolicLink(at: f.dbURL, withDestinationURL: real)
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.status != .ok)
        #expect(r.recent.isEmpty)
    }

    @Test func viewInsteadOfTableIsUnsupportedSchema() throws {
        let f = try ShazamFixture(); defer { f.remove() }
        try f.createDatabase(tagResultAsView: true)
        let r = ShazamLibrary(containerURL: f.container, shazamAppURL: noShazamApp).read(since: .distantPast, recentLimit: 20)
        #expect(r.status == .unsupportedSchema("ZSHTAGRESULTMO is not a table"))
    }
}
