import Foundation
import ImageIO
import UIKit

private actor ImageWorkLimiter {
    static let shared = ImageWorkLimiter(limit: 6)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// 메모리의 디코딩된 썸네일과 디스크의 원본 응답을 함께 재사용하는 이미지 파이프라인이다.
@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let urlCache = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 512 * 1_024 * 1_024,
            diskPath: "com.leeari95.NewEligaOrder.images"
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(for url: URL, targetSize: CGFloat) async -> UIImage? {
        let key = cacheKey(url: url, targetSize: targetSize)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let session = session
        let scale = UIScreen.main.scale
        let task = Task.detached(priority: .utility) {
            await ImageWorkLimiter.shared.acquire()
            let result = await Self.downloadAndDownsample(
                url: url,
                targetSize: targetSize,
                scale: scale,
                session: session
            )
            await ImageWorkLimiter.shared.release()
            return result
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            memoryCache.setObject(result, forKey: key as NSString, cost: result.memoryCost)
        }
        return result
    }

    func preload(_ urls: [URL], targetSize: CGFloat = 96, limit: Int = 32) {
        for url in Array(Set(urls)).prefix(limit) {
            let key = cacheKey(url: url, targetSize: targetSize)
            guard memoryCache.object(forKey: key as NSString) == nil, inFlight[key] == nil else { continue }
            Task(priority: .utility) { [weak self] in
                _ = await self?.image(for: url, targetSize: targetSize)
            }
        }
    }

    func removeAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        memoryCache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    private func cacheKey(url: URL, targetSize: CGFloat) -> String {
        "\(url.absoluteString)|\(Int(targetSize.rounded(.up)))"
    }

    nonisolated private static func downloadAndDownsample(
        url: URL,
        targetSize: CGFloat,
        scale: CGFloat,
        session: URLSession
    ) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let source = CGImageSourceCreateWithData(data as CFData, nil)
            else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int((targetSize * scale).rounded(.up))),
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: image, scale: scale, orientation: .up)
        } catch {
            return nil
        }
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
