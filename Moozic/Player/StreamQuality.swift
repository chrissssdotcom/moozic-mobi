import Foundation

/// `?format=&bitrate=` on `/tracks/{id}/stream`. Transcoding needs ffmpeg on the server and
/// transcoded streams can't seek. (Opus-in-Ogg isn't offered: AVPlayer can't play it.)
enum StreamQuality: String, CaseIterable, Identifiable {
    case original
    case mp3_320
    case mp3_192
    case mp3_128
    case aac_128
    case aac_64

    static let storageKey = "streamQuality"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original file"
        case .mp3_320: return "MP3 · 320 kbps"
        case .mp3_192: return "MP3 · 192 kbps"
        case .mp3_128: return "MP3 · 128 kbps"
        case .aac_128: return "AAC · 128 kbps"
        case .aac_64: return "AAC · 64 kbps"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .original: return []
        case .mp3_320: return [.init(name: "format", value: "mp3"), .init(name: "bitrate", value: "320")]
        case .mp3_192: return [.init(name: "format", value: "mp3"), .init(name: "bitrate", value: "192")]
        case .mp3_128: return [.init(name: "format", value: "mp3"), .init(name: "bitrate", value: "128")]
        case .aac_128: return [.init(name: "format", value: "aac"), .init(name: "bitrate", value: "128")]
        case .aac_64: return [.init(name: "format", value: "aac"), .init(name: "bitrate", value: "64")]
        }
    }

    var isSeekable: Bool { self == .original }

    static var current: StreamQuality {
        StreamQuality(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .original
    }
}
