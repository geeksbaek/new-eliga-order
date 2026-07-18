import Foundation
import UIKit

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
        let task = Task<UIImage?, Never>(priority: .utility) {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let source = UIImage(data: data, scale: UIScreen.main.scale)
                else { return nil }

                let scale = UIScreen.main.scale
                let pixelSize = CGSize(width: targetSize * scale, height: targetSize * scale)
                return await source.byPreparingThumbnail(ofSize: pixelSize) ?? source
            } catch {
                return nil
            }
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
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
