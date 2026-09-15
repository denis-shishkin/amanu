import CryptoKit
import Foundation

/// The one Whisper model Amanu supports as a first production default.
///
/// The URL is revision-pinned and the LFS object digest is checked after every
/// download. A response reaching 100% therefore is not enough to make it a
/// model: only a verified `.partial` file is renamed to the canonical path.
struct WhisperModelStore: Sendable {
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
        case badHTTPStatus(Int)
        case invalidSize(expected: Int64, actual: Int64)
        case invalidSHA256
        case missingDownloadedFile

        var description: String {
            switch self {
            case .badHTTPStatus(let status): return "whisper model download returned HTTP \(status)"
            case .invalidSize(let expected, let actual):
                return "whisper model is \(actual) bytes; expected \(expected)"
            case .invalidSHA256: return "whisper model SHA-256 does not match its manifest"
            case .missingDownloadedFile: return "whisper model download produced no file"
            }
        }
    }

    typealias ProgressHandler = @Sendable (Progress) -> Void
    typealias Downloader = @Sendable (
        _ source: URL,
        _ partial: URL,
        _ progress: @escaping ProgressHandler
    ) async throws -> Void

    /// Hugging Face's immutable revision which introduced this exact model.
    /// 574,041,195 bytes is 547.4 MiB, presented in the setup UI as about
    /// 550 MB while the progress bar uses the response's real byte counts.
    static let defaultManifest = Manifest(
        id: "large-v3-turbo-q5_0",
        fileName: "ggml-large-v3-turbo-q5_0.bin",
        revision: "98aa99a0a9db05ae2342309f5096248665f7cba3",
        downloadURL: URL(string:
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/98aa99a0a9db05ae2342309f5096248665f7cba3/ggml-large-v3-turbo-q5_0.bin?download=true"
        )!,
        expectedBytes: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2")

    static let advertisedDownloadBytes: Int64 = 550 * 1_048_576

    let directory: URL
    let manifest: Manifest
    private let downloader: Downloader

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/amanu/models/whisper", isDirectory: true),
        manifest: Manifest = WhisperModelStore.defaultManifest,
        downloader: @escaping Downloader = WhisperHTTPDownloader.download
    ) {
        self.directory = directory
        self.manifest = manifest
        self.downloader = downloader
    }

    var modelURL: URL { directory.appendingPathComponent(manifest.fileName) }
    var partialURL: URL { URL(fileURLWithPath: modelURL.path + ".partial") }

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

    func delete() throws {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            try FileManager.default.removeItem(at: modelURL)
        }
        if FileManager.default.fileExists(atPath: partialURL.path) {
            try FileManager.default.removeItem(at: partialURL)
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

    /// Incremental hashing keeps model verification at a fixed memory cost.
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

enum WhisperHTTPDownloader {
    static func download(
        source: URL,
        partial: URL,
        progress: @escaping WhisperModelStore.ProgressHandler
    ) async throws {
        let delegate = Delegate(partial: partial, progress: progress)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.begin(continuation: continuation)
                let task = session.dataTask(with: source)
                delegate.attach(task)
                task.resume()
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let partial: URL
        private let progress: WhisperModelStore.ProgressHandler
        private let lock = NSLock()
        private var file: FileHandle?
        private var continuation: CheckedContinuation<Void, Swift.Error>?
        private var task: URLSessionTask?
        private var received: Int64 = 0
        private var expected: Int64?
        private var finished = false
        private var cancelled = false

        init(partial: URL, progress: @escaping WhisperModelStore.ProgressHandler) {
            self.partial = partial
            self.progress = progress
        }

        func begin(continuation: CheckedContinuation<Void, Swift.Error>) {
            _ = FileManager.default.createFile(atPath: partial.path, contents: nil)
            let opened = Result { try FileHandle(forWritingTo: partial) }
            lock.withLock {
                self.continuation = continuation
                if case .success(let handle) = opened { file = handle }
            }
            if case .failure(let error) = opened { complete(.failure(error)) }
        }

        func attach(_ task: URLSessionTask) {
            lock.withLock {
                self.task = task
                if finished || cancelled { task.cancel() }
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                task?.cancel()
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completionHandler(.cancel)
                complete(.failure(WhisperModelStore.Error.badHTTPStatus(http.statusCode)))
                return
            }
            expected = response.expectedContentLength > 0 ? response.expectedContentLength : nil
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            do {
                try file?.write(contentsOf: data)
                received += Int64(data.count)
                progress(.init(receivedBytes: received, totalBytes: expected))
            } catch {
                dataTask.cancel()
                complete(.failure(error))
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Swift.Error?
        ) {
            if let error { complete(.failure(error)) }
            else { complete(.success(())) }
        }

        private func complete(_ result: Result<Void, Swift.Error>) {
            let continuation: CheckedContinuation<Void, Swift.Error>? = lock.withLock {
                guard !finished else { return nil }
                finished = true
                try? file?.close()
                file = nil
                let saved = self.continuation
                self.continuation = nil
                return saved
            }
            continuation?.resume(with: result)
        }
    }
}
