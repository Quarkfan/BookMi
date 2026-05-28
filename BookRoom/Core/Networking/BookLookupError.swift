import Foundation

enum BookLookupError: Error, LocalizedError {
    case networkError(String)
    case invalidResponse
    case notFound

    var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误: \(msg)"
        case .invalidResponse: return "服务器响应无效"
        case .notFound: return "未找到相关图书"
        }
    }
}
