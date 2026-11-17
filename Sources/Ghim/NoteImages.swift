import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Raw image bytes plus the file extension to store them under.
struct ImagePayload {
    var data: Data
    var ext: String

    static let maxPixel: CGFloat = 2400

    /// From an NSImage (pasted screenshot, browser image…): stored as PNG, downscaled if huge.
    init?(image: NSImage) {
        guard let rep = ImagePayload.bitmap(from: image),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        data = png
        ext = "png"
    }

    /// From a file on disk: keep the original bytes (keeps GIF animation, JPEG size…).
    init?(fileURL url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let d = try? Data(contentsOf: url), NSImage(data: d) != nil else { return nil }
        data = d
        ext = url.pathExtension.lowercased()
    }

    private static func bitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxPixel / max(w, h))
        if scale >= 1 { return NSBitmapImageRep(cgImage: cg) }
        let nw = Int(w * scale), nh = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage().map { NSBitmapImageRep(cgImage: $0) }
    }
}

enum ImagePasteboard {
    /// Image payloads on the pasteboard, or [] when it should be treated as text.
    static func payloads(from pb: NSPasteboard = .general) -> [ImagePayload] {
        // 1. image files copied in Finder
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true,
                                               .urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           !urls.isEmpty {
            return urls.compactMap(ImagePayload.init(fileURL:))
        }
        // 2. raw image data (screenshots ⌃⇧⌘4, "Copy Image" in a browser…) — but not when it is really text
        let types = pb.types ?? []
        let hasImage = types.contains(.png) || types.contains(.tiff) || types.contains(NSPasteboard.PasteboardType("public.jpeg"))
        let hasText = types.contains(.string)
        if hasImage && !hasText, let img = NSImage(pasteboard: pb), let p = ImagePayload(image: img) {
            return [p]
        }
        return []
    }

    static func hasImage(_ pb: NSPasteboard = .general) -> Bool { !payloads(from: pb).isEmpty }
}

enum ImageDrop {
    static let types: [UTType] = [.fileURL, .image]

    /// Loads images from dropped item providers, then calls back on the main thread.
    static func load(_ providers: [NSItemProvider], completion: @escaping ([ImagePayload]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var result: [ImagePayload] = []
        func add(_ p: ImagePayload?) {
            guard let p else { return }
            lock.lock(); result.append(p); lock.unlock()
        }
        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    add(url.flatMap(ImagePayload.init(fileURL:)))
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    add((obj as? NSImage).flatMap(ImagePayload.init(image:)))
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(result) }
    }
}

/// Small in-memory thumbnail cache so scrolling stays smooth.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    @MainActor func image(_ name: String) -> NSImage? {
        if let i = cache.object(forKey: name as NSString) { return i }
        guard let i = NSImage(contentsOf: Store.shared.imageURL(name)) else { return nil }
        cache.setObject(i, forKey: name as NSString)
        return i
    }

    func remove(_ name: String) { cache.removeObject(forKey: name as NSString) }
}

// MARK: - Thumbnails inside a note card

struct NoteImagesView: View {
    let note: Note
    @EnvironmentObject var store: Store

    var body: some View {
        let names = note.images
        if names.count == 1, let name = names.first {
            NoteThumb(noteID: note.id, name: name, single: true)
        } else if !names.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                ForEach(names, id: \.self) { NoteThumb(noteID: note.id, name: $0, single: false) }
            }
        }
    }
}

struct NoteThumb: View {
    let noteID: UUID
    let name: String
    let single: Bool
    @EnvironmentObject var store: Store
    @State private var hover = false

    var body: some View {
        let url = store.imageURL(name)
        Group {
            if let img = ImageCache.shared.image(name) {
                if single {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 200)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
                }
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                    .frame(height: 60)
                    .overlay(Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.tertiary))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button {
                    withAnimation(.snappy) { store.removeImage(name, from: noteID) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Xoá ảnh")
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help("Nhấp đúp để mở · kéo ra app khác để gửi")
        .contextMenu {
            Button("Mở ảnh") { NSWorkspace.shared.open(url) }
            Button("Sao chép ảnh") {
                if let img = NSImage(contentsOf: url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                }
            }
            Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Xoá ảnh", role: .destructive) { withAnimation(.snappy) { store.removeImage(name, from: noteID) } }
        }
    }
}
