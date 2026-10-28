//
//  PlaybackCoordinator.swift — the one and only audio player for the whole app.
//
//  Every AudioPlayer view (library rows, result panel) delegates to this shared
//  coordinator instead of owning its own AVAudioPlayer. That guarantees only a
//  single track can ever play: starting a new track automatically stops the
//  one that was playing.
//
//  Views register/unregister on appear/disappear so hiding a pane (e.g. the
//  library) only stops playback when no other live view is showing the same
//  track — e.g. a song that just finished in the result panel keeps playing
//  if you hide the library while it's audible there.
//

import AVFoundation
import Combine

@MainActor
final class PlaybackCoordinator: ObservableObject {
    static let shared = PlaybackCoordinator()

    /// The track currently loaded in the player (nil when nothing is loaded).
    @Published private(set) var url: URL?
    /// Whether the loaded track is actually producing sound right now.
    @Published private(set) var isPlaying = false
    /// Playback position of the loaded track, in seconds.
    @Published private(set) var current: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    /// How many live AudioPlayer views are showing each URL.
    private var liveViews: [URL: Int] = [:]

    private init() {}

    // MARK: - View lifecycle

    func register(_ url: URL) {
        liveViews[url, default: 0] += 1
    }

    func unregister(_ url: URL) {
        guard let count = liveViews[url] else { return }
        if count <= 1 {
            liveViews[url] = nil
        } else {
            liveViews[url] = count - 1
        }
        // The last view showing this track went away — stop the playback.
        if self.url == url {
            stop()
        }
    }

    // MARK: - Transport

    /// Start (or resume) the given track, stopping whatever else is playing.
    func play(_ url: URL) {
        if self.url == url, let p = player {
            // Same track: resume. If it ran to the end, start over from zero.
            if p.duration > 0, p.currentTime >= p.duration - 0.05 {
                p.currentTime = 0
            }
            current = p.currentTime
            p.play()
            isPlaying = true
            startTicker()
            return
        }

        // A different track: stop the previous one first — only one plays at a time.
        stop()

        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.prepareToPlay()
        player = p
        self.url = url
        current = 0
        isPlaying = true
        p.play()
        startTicker()
    }

    /// Pause the loaded track (if any).
    func pause() {
        guard let p = player, p.isPlaying else { return }
        p.pause()
        isPlaying = false
    }

    /// Move the loaded track to an absolute position, in seconds.
    func seek(to time: TimeInterval) {
        guard let p = player else { return }
        p.currentTime = min(max(time, 0), max(p.duration, 0))
        current = p.currentTime
    }

    /// Stop playback and release the player.
    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        url = nil
        isPlaying = false
        current = 0
    }

    // MARK: - Ticker

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            // Promote to a strong constant for the tick's duration (the timer
            // itself keeps only the weak reference, so no retain cycle).
            guard let self else { return }
            Task { @MainActor in
                guard let p = self.player else { return }
                self.current = p.currentTime
                if !p.isPlaying {
                    // The track ran to the end: reset so a replay starts clean.
                    self.isPlaying = false
                    p.currentTime = 0
                    self.current = 0
                }
            }
        }
    }
}
