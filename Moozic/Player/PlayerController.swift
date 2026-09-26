import AVFoundation
import Combine
import MediaPlayer
import UIKit

enum RepeatMode: String, CaseIterable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

/// The play queue and the AVPlayer behind it, plus lock-screen / Control Center integration.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var errorMessage: String?

    var current: Track? { index.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var canSeek: Bool { currentQuality.isSeekable && duration > 0 }

    private let player = AVPlayer()
    private weak var session: SessionStore?
    private var originalOrder: [Track] = []
    private var currentQuality: StreamQuality = .original
    private var loadGeneration = 0
    private var scrobbled = false
    private var listened: Double = 0
    private var lastTick: Double?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var itemCancellables = Set<AnyCancellable>()
    private var artworkTrackId: Int?
    private var artwork: MPMediaItemArtwork?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        configureAudioSession()
        configureRemoteCommands()
        observePlayer()
        NotificationCenter.default.addObserver(forName: .moozicDidSignOut, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func attach(_ session: SessionStore) {
        self.session = session
    }

    // MARK: Queue control

    func play(_ tracks: [Track], startAt start: Int = 0, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        originalOrder = tracks
        if shuffle {
            queue = tracks.shuffled()
            isShuffled = true
            load(index: 0)
        } else {
            queue = tracks
            isShuffled = false
            load(index: min(max(start, 0), tracks.count - 1))
        }
    }

    func playNext(_ tracks: [Track]) {
        guard let index else { return play(tracks) }
        queue.insert(contentsOf: tracks, at: index + 1)
        originalOrder.append(contentsOf: tracks)
    }

    func addToQueue(_ tracks: [Track]) {
        guard index != nil else { return play(tracks) }
        queue.append(contentsOf: tracks)
        originalOrder.append(contentsOf: tracks)
    }

    func jump(to newIndex: Int) {
        guard queue.indices.contains(newIndex) else { return }
        load(index: newIndex)
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard let index else { return }
        let removingCurrent = offsets.contains(index)
        let before = offsets.filter { $0 < index }.count
        let removedIds = Set(offsets.map { queue[$0].id })
        queue.remove(atOffsets: offsets)
        originalOrder.removeAll { removedIds.contains($0.id) && !queue.contains($0) }
        if queue.isEmpty { return stop() }
        if removingCurrent {
            load(index: min(index - before, queue.count - 1))
        } else {
            self.index = index - before
        }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let index else { return }
        let currentId = queue[index].id
        let currentOccurrence = queue[..<index].filter { $0.id == currentId }.count
        queue.move(fromOffsets: source, toOffset: destination)
        // Find the same occurrence of the playing track again.
        var seen = 0
        for (i, track) in queue.enumerated() where track.id == currentId {
            if seen == currentOccurrence { self.index = i; break }
            seen += 1
        }
    }

    func toggleShuffle() {
        guard let current else { return }
        if isShuffled {
            queue = originalOrder
            index = queue.firstIndex(of: current) ?? 0
        } else {
            var rest = queue
            if let i = index { rest.remove(at: i) }
            queue = [current] + rest.shuffled()
            index = 0
        }
        isShuffled.toggle()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard player.currentItem != nil else {
            if let index { load(index: index) }
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func pause() {
        player.pause()
    }

    func next() {
        guard let index, !queue.isEmpty else { return }
        if index + 1 < queue.count {
            load(index: index + 1)
        } else if repeatMode == .all {
            load(index: 0)
        } else {
            player.pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard let index else { return }
        if elapsed > 3 || index == 0 {
            seek(to: 0)
        } else {
            load(index: index - 1)
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = max(0, seconds)
        lastTick = nil
        updateNowPlaying()
    }

    func stop() {
        loadGeneration += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemCancellables = []
        queue = []
        originalOrder = []
        index = nil
        elapsed = 0
        duration = 0
        isShuffled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Loading

    private func load(index newIndex: Int) {
        guard let session, let api = session.api, queue.indices.contains(newIndex) else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let track = queue[newIndex]
        index = newIndex
        elapsed = 0
        duration = track.duration ?? 0
        scrobbled = false
        listened = 0
        lastTick = nil
        errorMessage = nil
        currentQuality = StreamQuality.current
        player.pause()
        updateNowPlaying()

        Task {
            let headers = await session.mediaHeaders()
            guard generation == self.loadGeneration else { return }
            let url = api.url(track.streamUrl, query: self.currentQuality.queryItems)
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 30
            self.player.replaceCurrentItem(with: item)
            try? AVAudioSession.sharedInstance().setActive(true)
            self.player.play()
            self.observe(item: item, generation: generation)
            self.loadArtwork(for: track)
        }
    }

    private func observe(item: AVPlayerItem, generation: Int) {
        itemCancellables = []
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, generation == self.loadGeneration else { return }
                if status == .failed {
                    self.errorMessage = item.error?.localizedDescription ?? "Couldn't play this track."
                    self.isPlaying = false
                    self.isBuffering = false
                } else if status == .readyToPlay {
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                    self.updateNowPlaying()
                }
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, generation == self.loadGeneration else { return }
                self.itemDidFinish()
            }
            .store(in: &itemCancellables)
    }

    private func itemDidFinish() {
        if repeatMode == .one {
            seek(to: 0)
            player.play()
        } else {
            next()
        }
    }

    private func observePlayer() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status == .playing || status == .waitingToPlayAtSpecifiedRate
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self.updateNowPlaying()
            }
            .store(in: &cancellables)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        elapsed = seconds
        if let lastTick, isPlaying {
            let delta = seconds - lastTick
            if delta > 0, delta < 2 { listened += delta }
        }
        lastTick = seconds
        scrobbleIfNeeded()
    }

    /// Like the web player: record a play after 30 s of listening (or half the track, if shorter).
    private func scrobbleIfNeeded() {
        guard !scrobbled, let track = current, let api = session?.api else { return }
        let threshold = min(30, max(duration, 1) / 2)
        guard listened >= threshold else { return }
        scrobbled = true
        Task { try? await api.recordPlay(trackId: track.id) }
    }

    // MARK: System integration

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
                guard let self, self.canSeek else { return .commandFailed }
                self.seek(to: event.positionTime)
                return .success
            }
        }
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.name,
            MPMediaItemPropertyAlbumTitle: track.album.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: index ?? 0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
        ]
        if artworkTrackId == track.album.id, let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = canSeek
    }

    private func loadArtwork(for track: Track) {
        guard artworkTrackId != track.album.id, let images = session?.images else {
            updateNowPlaying()
            return
        }
        artworkTrackId = track.album.id
        artwork = nil
        let albumId = track.album.id
        Task {
            guard let image = await images.image(for: track.coverUrl), self.artworkTrackId == albumId else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    /// Nonisolated on purpose: MediaPlayer calls the image handler off the main thread.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
