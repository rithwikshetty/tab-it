import Foundation
import UIKit
import Supabase

enum ReceiptStorage {
    static let bucket = "receipts"

    private static let maxBytes = 9_500_000
    private static let primaryQuality: CGFloat = 0.92
    /// Hard cap on stored pixel dimensions. A receipt is fully readable well below
    /// this, and it bounds the decoded bitmap at every display site (and the
    /// stored file size) regardless of the source photo's resolution.
    private static let maxStoredEdge: CGFloat = 2048

    enum Failure: Error, LocalizedError {
        case invalidImage
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Couldn't read the selected image."
            case .imageTooLarge: "The selected image is too large."
            }
        }
    }

    static func storagePath(tripID: UUID, expenseID: UUID) -> String {
        "\(tripID.uuidString.lowercased())/\(expenseID.uuidString.lowercased()).jpg"
    }

    static func persistPendingUpload(jpeg: Data, tripID: UUID, expenseID: UUID) throws -> String {
        guard jpeg.count <= maxBytes else { throw Failure.imageTooLarge }

        let path = storagePath(tripID: tripID, expenseID: expenseID)
        try FileManager.default.createDirectory(
            at: pendingDirectoryURL,
            withIntermediateDirectories: true
        )
        try jpeg.write(to: pendingFileURL(for: path), options: .atomic)
        return path
    }

    static func prepareJPEG(from data: Data) throws -> Data {
        guard let source = UIImage(data: data) else { throw Failure.invalidImage }

        // Always cap dimensions first: this bounds the stored file and every
        // future decode, rather than only kicking in when the byte cap is hit.
        let image = downscale(source, maxEdge: maxStoredEdge)

        if let jpeg = image.jpegData(compressionQuality: primaryQuality), jpeg.count <= maxBytes {
            return jpeg
        }

        var edge = max(image.size.width, image.size.height) * 0.75
        var smallestJPEG: Data?
        while edge >= 480 {
            let resized = downscale(image, maxEdge: edge)
            if let jpeg = resized.jpegData(compressionQuality: primaryQuality) {
                if smallestJPEG == nil || jpeg.count < smallestJPEG!.count { smallestJPEG = jpeg }
                if jpeg.count <= maxBytes { return jpeg }
            }
            edge *= 0.75
        }

        if let smallestJPEG, smallestJPEG.count <= maxBytes {
            return smallestJPEG
        }
        throw Failure.imageTooLarge
    }

    static func upload(jpeg: Data, tripID: UUID, expenseID: UUID) async throws -> String {
        guard jpeg.count <= maxBytes else { throw Failure.imageTooLarge }

        let path = storagePath(tripID: tripID, expenseID: expenseID)
        try await upload(jpeg: jpeg, path: path)
        return path
    }

    static func uploadPendingReceipt(path: String) async throws {
        let fileURL = pendingFileURL(for: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let jpeg = try Data(contentsOf: fileURL)
        try await upload(jpeg: jpeg, path: path)
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func signedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        try await SupabaseClientProvider.shared.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: expiresIn)
    }

    private static func upload(jpeg: Data, path: String) async throws {
        guard jpeg.count <= maxBytes else { throw Failure.imageTooLarge }

        let storage = SupabaseClientProvider.shared.storage.from(bucket)
        _ = try await storage.upload(
            path,
            data: jpeg,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
    }

    private static var pendingDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReceiptUploads", isDirectory: true)
    }

    private static func pendingFileURL(for path: String) -> URL {
        pendingDirectoryURL.appendingPathComponent(
            path.replacingOccurrences(of: "/", with: "__"),
            isDirectory: false
        )
    }

    private static func downscale(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
