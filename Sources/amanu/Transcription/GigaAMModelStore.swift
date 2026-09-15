import CryptoKit
import Foundation

/// The revision-pinned GigaAM-v3 model consumed by transcribe.cpp.
struct GigaAMModelStore: Sendable {
    struct Manifest: Equatable, Sendable {
        let id: String
        let fileName: String
        let revision: String
        let downloadURL: URL
        let expectedBytes: Int64
        let sha256: String
    }

    struct Progress: Equatable, Sendable {
        let receivedBytes: Int64
        let totalBytes: Int64?

        var fraction: Double? {
            guard let totalBytes, totalBytes > 0 else { return nil }
            return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
        }
    }

    enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case invalidSize(expected: Int64, actual: Int64)
        case invalidSHA256
        case missingDownloadedFile

        var description: String {
            switch self {
            case .invalidSize(let expected, let actual):
                return "GigaAM model is \(actual) bytes; expected \(expected)"
            case .invalidSHA256: return "GigaAM model SHA-256 does not match its manifest"
            case .missingDownloadedFile: return "GigaAM model download produced no file"
            }
        }
    }

    typealias ProgressHandler = @Sendable (Progress) -> Void
    typealias Downloader = @Sendable (
        _ source: URL,
        _ partial: URL,
        _ progress: @escaping ProgressHandler
    ) async throws -> Void

    // Handy defaults to Q8_0. It keeps the CTC decoder fast while preserving
    // punctuation and Cyrillic casing, and is still only 259.5 MiB.
    static let defaultManifest = Manifest(
        id: "gigaam-v3-e2e-ctc-q8_0",
        fileName: "gigaam-v3-e2e-ctc-Q8_0.gguf",
        revision: "075dff81f843cf23d22b4ce943ffdc4dd8650cd7",
        downloadURL: URL(string:
            "https://huggingface.co/handy-computer/gigaam-v3-e2e-ctc-gguf/resolve/075dff81f843cf23d22b4ce943ffdc4dd8650cd7/gigaam-v3-e2e-ctc-Q8_0.gguf?download=true"
        )!,
        expectedBytes: 272_151_136,
        sha256: "9ccce4750dc813a493d96ca15ee251712bedec15ac9a02fa3d2bd732f08ae5eb")

    static let advertisedDownloadBytes: Int64 = defaultManifest.expectedBytes

    let directory: URL
    let manifest: Manifest
    private let downloader: Downloader

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/amanu/models/gigaam", isDirectory: true),
        manifest: Manifest = GigaAMModelStore.defaultManifest,
        downloader: @escaping Downloader = { source, partial, progress in
            try await WhisperHTTPDownloader.download(source: source, partial: partial) { update in
                progress(.init(
                    receivedBytes: update.receivedBytes,
                    totalBytes: update.totalBytes))
            }
        }
    ) {
        self.directory = directory
        self.manifest = manifest
        self.downloader = downloader
    }

    var modelURL: URL { directory.appendingPathComponent(manifest.fileName) }
    private var partialURL: URL { URL(fileURLWithPath: modelURL.path + ".partial") }

    var bytesOnDisk: Int {
        (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    func download(progress: @escaping ProgressHandler = { _ in }) async throws -> URL {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            do {
                try Self.verify(modelURL, against: manifest)
                return modelURL
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: modelURL)
            }
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: partialURL)
        do {
            try await downloader(manifest.downloadURL, partialURL, progress)
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: partialURL.path) else {
                throw Error.missingDownloadedFile
            }
            try Self.verify(partialURL, against: manifest)
            try FileManager.default.moveItem(at: partialURL, to: modelURL)
            return modelURL
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
    }

    private static func verify(_ url: URL, against manifest: Manifest) throws {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
        guard size == manifest.expectedBytes else {
            throw Error.invalidSize(expected: manifest.expectedBytes, actual: size)
        }
        guard try sha256(of: url) == manifest.sha256.lowercased() else {
            throw Error.invalidSHA256
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try file.read(upToCount: 1_048_576), !data.isEmpty else { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
