import Foundation
import Testing
@testable import NotchCurtain

struct MusicProviderTests {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    @Test func parsesAdapterTrackAndArtwork() throws {
        let track = try #require(MusicTrack.parse(fixture("adapter-playing")))
        #expect(track.title == "Fixture Track")
        #expect(track.artist == "Fixture Artist")
        #expect(track.album == "Fixture Album")
        #expect(track.artwork == Data("hello".utf8))
        #expect(track.artworkMimeType == "image/png")
        #expect(track.playing)
        #expect(track.duration == 180)
        #expect(track.bundleIdentifier == "com.google.Chrome")
        #expect(track.currentTime(at: Date(timeIntervalSince1970: track.timestamp + 10)) == 52.5)
    }

    @Test func playingProgressTicksDoNotChangeVisibleTrackState() {
        let first = MusicTrack(title: "Track", artist: "Artist", album: nil, artwork: nil, artworkMimeType: nil,
                               playing: true, elapsedTime: 10, duration: 100, timestamp: 1_700_000_000, bundleIdentifier: "player")
        let nextTick = MusicTrack(title: "Track", artist: "Artist", album: nil, artwork: nil, artworkMimeType: nil,
                                  playing: true, elapsedTime: 11, duration: 100, timestamp: 1_700_000_001, bundleIdentifier: "player")
        #expect(first.hasSameVisibleState(as: nextTick))
        #expect(!first.hasSameVisibleState(as: MusicTrack(title: "Other", artist: "Artist", album: nil, artwork: nil, artworkMimeType: nil,
                                                          playing: true, elapsedTime: 11, duration: 100, timestamp: 1_700_000_001, bundleIdentifier: "player")))
    }

    @Test func parsesPausedTrackWithoutArtwork() throws {
        let track = try #require(MusicTrack.parse(fixture("adapter-paused")))
        #expect(!track.playing)
        #expect(track.artwork == nil)
        #expect(track.artworkMimeType == nil)
    }

    @Test func nullMeansNoTrack() {
        #expect(MusicTrack.parse(try! fixture("adapter-null")) == nil)
    }

    @Test func parsesTrackWithoutArtwork() throws {
        let track = try #require(MusicTrack.parse(fixture("adapter-no-artwork")))
        #expect(track.title == "Track Without Cover")
        #expect(track.artist == "Artist")
        #expect(track.artwork == nil)
    }

    @Test func parsesFullStreamEnvelope() throws {
        let track = try #require(MusicTrack.parse(fixture("adapter-stream")))
        #expect(track.title == "Fixture Track")
        #expect(track.playing)
        #expect(track.timestamp > 1_700_000_000)
    }

    @Test func recognizesSoundCloudChromeWebApp() {
        #expect(mediaSourceName("com.google.Chrome.app.example", title: "Track", artist: "Artist") == "SoundCloud")
        #expect(mediaSourceName("com.google.Chrome.app.example") == "SoundCloud")
        #expect(mediaSourceName("com.google.Chrome", title: "Track", artist: "Artist") == "Google Chrome")
        #expect(mediaSourceName("com.apple.Safari") == "Safari")
    }
}
