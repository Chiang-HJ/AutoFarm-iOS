import Foundation
import UniformTypeIdentifiers
import UIKit
import idevice

public final class PairingStore: ObservableObject {
    public static let shared = PairingStore()

    @Published public private(set) var hasPairingFile = false
    @Published public var lastError: String?

    public static let fileName = "rp_pairing_file.plist"
    public static let supportedTypes: [UTType] = {
        var types: [UTType] = [
            .item,
            .data,
            .propertyList,
            .xml,
        ]
        for ext in ["plist", "mobiledevicepairing", "mobiledevicepair"] {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        if let custom = UTType("com.autofarm.rppairing") {
            types.append(custom)
        }
        return types
    }()

    public static var directoryURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public var pairingURL: URL {
        Self.directoryURL.appendingPathComponent(Self.fileName)
    }

    public var pairingPath: String { pairingURL.path }

    public init() {
        refresh()
        if !hasPairingFile {
            // 自動偵測並載入預先打包在 App Bundle 內的專屬憑證
            if let bundleURL = Bundle.main.url(forResource: "rp_pairing_file", withExtension: "plist") ??
                               Bundle.main.url(forResource: "pairingFile", withExtension: "plist") ??
                               Bundle.main.url(forResource: "rp_pairing_file", withExtension: "mobiledevicepairing") {
                if let data = try? Data(contentsOf: bundleURL) {
                    try? installPairingData(data)
                }
            }
            refresh()
        }
    }

    public func refresh() {
        hasPairingFile = FileManager.default.fileExists(atPath: pairingURL.path)
    }

    @discardableResult
    public func generateNewRemotePairing() -> URL? {
        var handle: OpaquePointer?
        if let err = "AutoFarm".withCString({ rp_pairing_file_generate($0, &handle) }) {
            idevice_error_free(err)
            return nil
        }
        guard let handle else { return nil }
        defer { rp_pairing_file_free(handle) }

        let destURL = Self.directoryURL.appendingPathComponent(Self.fileName)
        if let writeErr = destURL.path.withCString({ rp_pairing_file_write(handle, $0) }) {
            idevice_error_free(writeErr)
            return nil
        }
        refresh()
        return destURL
    }

    public static func availablePairings() -> [URL] {
        let dir = directoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "plist" || $0.pathExtension == "mobiledevicepairing" || $0.lastPathComponent == fileName }
    }

    public static func savePairing(from sourceURL: URL) throws -> URL {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: sourceURL)
        let destURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        try data.write(to: destURL, options: .atomic)

        // 也複製一份為預設 fileName
        let defaultDest = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: defaultDest)
        try? data.write(to: defaultDest, options: .atomic)

        shared.refresh()
        return destURL
    }

    public func importPairing(from sourceURL: URL) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: sourceURL)
        try installPairingData(data)
    }

    public func importPairingFromClipboard() throws {
        let board = UIPasteboard.general

        if let url = board.url ?? board.urls?.first {
            if url.isFileURL {
                try importPairing(from: url)
                return
            }
        }

        let candidates: [Data?] = [
            board.data(forPasteboardType: "com.apple.property-list"),
            board.data(forPasteboardType: UTType.propertyList.identifier),
            board.data(forPasteboardType: UTType.xml.identifier),
            board.data(forPasteboardType: UTType.data.identifier),
            board.string?.data(using: .utf8),
        ]

        guard let data = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw PairingImportError.emptyClipboard
        }
        try installPairingData(data)
    }

    public func removePairing() throws {
        if FileManager.default.fileExists(atPath: pairingURL.path) {
            try FileManager.default.removeItem(at: pairingURL)
        }
        hasPairingFile = false
    }

    private func installPairingData(_ data: Data) throws {
        guard looksLikePairingPlist(data) else {
            throw PairingImportError.invalidContents
        }

        let dir = Self.directoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: pairingURL.path) {
            try FileManager.default.removeItem(at: pairingURL)
        }
        try data.write(to: pairingURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairingURL.path)
        hasPairingFile = true
        lastError = nil
    }

    private func looksLikePairingPlist(_ data: Data) -> Bool {
        if let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return obj is [AnyHashable: Any] || obj is [Any]
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return text.hasPrefix("<?xml") || text.hasPrefix("bplist") || text.contains("<plist")
    }
}

public enum PairingImportError: LocalizedError {
    case emptyClipboard
    case invalidContents

    public var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return "剪貼簿為空。請複製 RPPairing plist 內容後再試一次。"
        case .invalidContents:
            return "非有效的 RPPairing plist 憑證檔案。"
        }
    }
}
