import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct ShelfItem: Identifiable {
    let id: UUID
    let name: String
    let url: URL?
    let icon: NSImage
    let missing: Bool
}

final class FileShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var dropTargeted = false

    private struct Record: Codable {
        var id: UUID
        var name: String
        var bookmark: Data
    }

    private var records: [Record] = []
    private let limit = 12

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else {
            items = []
            return
        }
        records = (try? JSONDecoder().decode([Record].self, from: data)) ?? []
        rebuild()
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] object, _ in
                    guard let url = object as? URL else { return }
                    DispatchQueue.main.async {
                        self?.add(url: url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                    guard let data,
                          let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let url = URL(string: string) else { return }
                    DispatchQueue.main.async {
                        self?.add(url: url)
                    }
                }
            }
        }
        return accepted
    }

    func remove(_ item: ShelfItem) {
        records.removeAll { $0.id == item.id }
        persist()
        rebuild()
    }

    private func add(url: URL) {
        guard url.isFileURL else { return }
        let path = url.standardizedFileURL.path
        if records.contains(where: { resolve($0).url?.standardizedFileURL.path == path }) {
            return
        }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let record = Record(id: UUID(), name: url.lastPathComponent, bookmark: bookmark)
            records.append(record)
            if records.count > limit {
                records.removeFirst(records.count - limit)
            }
            persist()
            rebuild()
        } catch {
            AppLog.general.error("Shelf bookmark failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rebuild() {
        var updates: [(Int, Data)] = []
        let built: [ShelfItem] = records.enumerated().map { index, record in
            let resolved = resolve(record)
            if resolved.stale, let url = resolved.url,
               let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                updates.append((index, bookmark))
            }
            let url = resolved.url
            let missing: Bool
            if let url {
                missing = !FileManager.default.fileExists(atPath: url.path)
            } else {
                missing = true
            }
            let icon: NSImage
            if let url, !missing {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                icon = NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
            }
            return ShelfItem(id: record.id, name: record.name, url: missing ? nil : url, icon: icon, missing: missing)
        }
        for update in updates {
            records[update.0].bookmark = update.1
        }
        items = built
        if !updates.isEmpty {
            persist()
        }
    }

    private func resolve(_ record: Record) -> (url: URL?, stale: Bool) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: record.bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return (nil, false)
        }
        return (url, stale)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            AppLog.general.error("Shelf save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Notchling", isDirectory: true)
    }

    private var storeURL: URL {
        directoryURL.appendingPathComponent("shelf.json")
    }
}
