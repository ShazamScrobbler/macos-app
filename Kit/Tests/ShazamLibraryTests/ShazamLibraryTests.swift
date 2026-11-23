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
        #expect(lib.tags(withPKs: [pk, 999])[pk]?.track.title == "One")
        #expect(lib.tags(withPKs: [pk, 999])[999] == nil)
    }
}
