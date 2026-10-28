//
//  AudioPlayer.swift — a compact inline player. All playback goes through the
//  shared PlaybackCoordinator, so only one track can play at a time: starting
//  a new track (in any library row or the result panel) automatically stops
//  the one that was playing. The total time comes from a cheap WAV-header parse.
//

import SwiftUI
import AVFoundation

struct AudioPlayer: View {
    let url: URL
    @ObservedObject private var coordinator = PlaybackCoordinator.shared

    @State private var current: TimeInterval = 0
    @State private var isScrubbing = false

    /// True when this view's track is the one loaded in the shared player.
    private var isActive: Bool { coordinator.url == url }

    private var isPlaying: Bool { isActive && coordinator.isPlaying }

    private var duration: TimeInterval { SongLibrary.wavDuration(url) ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if isPlaying {
                    coordinator.pause()
                } else {
                    coordinator.play(url)
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            Slider(value: $current, in: 0...max(duration, 0.001)) { editing in
                isScrubbing = editing
                if !editing, isActive { coordinator.seek(to: current) }
            }
            .disabled(duration == 0 || !isActive)

            Text(timeString(current))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
        .onAppear { coordinator.register(url) }
        .onDisappear { coordinator.unregister(url) }
        .onChange(of: coordinator.url) { _, _ in
            // Another track took over the shared player — reset this dial.
            if !isActive { current = 0 }
        }
        .onChange(of: coordinator.current) { _, newValue in
            if isActive, !isScrubbing { current = newValue }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
