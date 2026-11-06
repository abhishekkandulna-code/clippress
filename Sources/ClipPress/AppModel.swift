import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case exporting(progress: Double, startedAt: Date)
    }

    @Published var clips: [Clip] = []
    @Published var settings = ExportSettings()
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var importingCount = 0
    @Published var banner: Banner?

    private var exporter: Exporter?
    private var exportURL: URL?

    var isExporting: Bool { phase != .idle }
    var plan: ExportPlan? { ExportPlan(clips: clips, settings: settings) }
    var totalSourceBytes: Int64 { clips.reduce(0) { $0 + $1.fileSize } }
    var totalDuration: Double { clips.reduce(0) { $0 + $1.duration.seconds } }

    var primaryActionTitle: String {
        clips.count > 1 ? "Join & compress" : "Compress video"
    }

    // MARK: Adding and arranging clips

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        panel.prompt = "Add"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await self?.add(urls) }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isExporting else { return false }
        let collector = DropCollector(count: providers.count)
        let group = DispatchGroup()
        for (index, provider) in providers.enumerated() where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.set(url, at: index) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            Task { @MainActor in await self?.add(collector.urls) }
        }
        return true
    }

    func add(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        importingCount += urls.count
        defer { importingCount -= urls.count }

        // Read files in parallel, but keep the order the user picked them in.
        let results = await withTaskGroup(of: (Int, Result<Clip, Error>).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    do { return (index, .success(try await Clip.load(url))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<Clip, Error>)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }
        }

        var failed: [String] = []
        for (index, result) in results {
            switch result {
            case .success(let clip): clips.append(clip)
            case .failure: failed.append(urls[index].lastPathComponent)
            }
        }

        if let first = failed.first {
            let subject = failed.count == 1 ? "“\(first)”" : "\(failed.count) files"
            banner = Banner(kind: .error, message: "Couldn't open \(subject). macOS can't read this format. Convert it to MP4, MOV or M4V and try again.")
        } else if banner?.kind == .error {
            banner = nil
        }
    }

    func move(_ clip: Clip, by offset: Int) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let target = index + offset
        guard clips.indices.contains(target) else { return }
        clips.swapAt(index, target)
    }

    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
    }

    // MARK: Export

    func export() {
        guard !isExporting, let plan, let first = clips.first else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        let stem = first.url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(stem)-\(clips.count > 1 ? "joined" : "compressed").mp4"
        panel.directoryURL = first.url.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.run(plan, to: url) }
        }
    }

    func cancelExport() {
        exporter?.cancel()
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Stops an export because the app is quitting, and deletes the half-written file.
    func abandonExportForQuit() {
        exporter?.cancel()
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
    }

    private func run(_ plan: ExportPlan, to url: URL) {
        if let shortfall = Self.diskShortfall(for: plan, at: url) {
            banner = Banner(kind: .error, message: shortfall)
            return
        }

        let exporter = Exporter()
        self.exporter = exporter
        exportURL = url
        banner = nil
        phase = .exporting(progress: 0, startedAt: Date())
        let clips = self.clips
        let codec = settings.codec
        let sourceBytes = totalSourceBytes
        // Long exports run for hours: keep the Mac from idle-sleeping and the app from App Nap.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Exporting a video"
        )

        Task {
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                phase = .idle
                self.exporter = nil
                exportURL = nil
            }
            do {
                try await exporter.export(clips, plan: plan, codec: codec, to: url) { [weak self] fraction in
                    Task { @MainActor in self?.updateProgress(fraction) }
                }
                let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                banner = Banner(kind: .success, message: Self.savedMessage(url, bytes: bytes, sourceBytes: sourceBytes), revealURL: url)
            } catch is CancellationError {
                banner = Banner(kind: .info, message: "Export cancelled. Nothing was saved.")
            } catch {
                banner = Banner(kind: .error, message: "Couldn't finish the export: \(error.localizedDescription) Try a lower resolution or the H.264 format.")
            }
        }
    }

    /// Explains the problem if the destination disk can't hold the export, or returns nil.
    private static func diskShortfall(for plan: ExportPlan, at url: URL) -> String? {
        let values = try? url.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        // Headroom for the estimate being low; fast-start briefly writes the file a second time.
        let needed = Int64(Double(plan.estimatedBytes) * (plan.optimizesForStreaming ? 2.2 : 1.2))
        guard free < needed else { return nil }
        return "Not enough free space. This export needs about \(Format.bytes(needed)) and the disk has \(Format.bytes(free)). Save to another disk or free up space."
    }

    private func updateProgress(_ fraction: Double) {
        guard case .exporting(_, let startedAt) = phase else { return }
        phase = .exporting(progress: fraction, startedAt: startedAt)
    }

    private static func savedMessage(_ url: URL, bytes: Int64, sourceBytes: Int64) -> String {
        var message = "Saved “\(url.lastPathComponent)”, \(Format.bytes(bytes))"
        if sourceBytes > 0, bytes > 0, bytes < sourceBytes {
            message += ", \(Int((1 - Double(bytes) / Double(sourceBytes)) * 100))% smaller"
        }
        return message + "."
    }
}

/// Collects dropped file URLs from callbacks that arrive on arbitrary threads.
private final class DropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [URL?]

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func set(_ url: URL, at index: Int) {
        lock.lock()
        slots[index] = url
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    static func timeLeft(_ seconds: Double) -> String {
        if seconds < 60 { return "Less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "About \(minutes) min left" }
        return "About \(minutes / 60) h \(minutes % 60) min left"
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumIntegerDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// 2 → "2", 1.25 → "1.25", 0.5 → "0.5".
    static func decimal(_ value: Double) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
