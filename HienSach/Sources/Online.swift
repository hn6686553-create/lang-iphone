import Foundation

struct OnlineBook: Decodable, Identifiable {
    let id: String
    let title: String
    let note: String
    let file: String
    let sha256: String
}
enum OnlineShelf {
    static let base = URL(string:"https://raw.githubusercontent.com/hn6686553-create/lang-iphone/hien-sach/HienSach/Catalog/")!
    static func catalog() async throws -> [OnlineBook] {
        let (data,response) = try await URLSession.shared.data(from:base.appendingPathComponent("index.json"))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 200_000 else {
            throw ReaderFailure("Chưa tải được danh mục. Hãy kiểm tra kết nối rồi thử lại.")
        }
        return try JSONDecoder().decode([OnlineBook].self,from:data)
    }
}
final class BookDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var result: CheckedContinuation<(URL,String),Error>?
    private var transfer: URLSessionDownloadTask?
    private var cancelled = false
    private var sizeExceeded = false
    private let progress: @Sendable (Double?) -> Void
    private let input: URL
    init(_ url:URL, progress:@escaping @Sendable (Double?) -> Void) { input=url; self.progress=progress }
    func run() async throws -> (URL,String) {
        guard input.scheme?.lowercased() == "https", input.host != nil else { throw ReaderFailure("Hãy nhập đường dẫn HTTPS tới tệp sách.") }
        return try await withTaskCancellationHandler(operation:{
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else { lock.unlock(); continuation.resume(throwing:CancellationError()); return }
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForResource = 240
                let session=URLSession(configuration:config,delegate:self,delegateQueue:nil)
                let task=session.downloadTask(with:input)
                transfer=task; result=continuation; lock.unlock(); task.resume()
            }
        },onCancel:{ self.cancel() })
    }
    private func cancel() { lock.lock(); cancelled=true; let task=transfer; lock.unlock(); task?.cancel() }
    private func complete(_ outcome:Result<(URL,String),Error>, _ session:URLSession) {
        lock.lock(); let continuation=result; result=nil; transfer=nil; lock.unlock()
        continuation?.resume(with:outcome); session.finishTasksAndInvalidate()
    }
    func urlSession(_ session:URLSession, task:URLSessionTask, willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest, completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(request.url?.scheme?.lowercased()=="https" ? request : nil)
    }
    func urlSession(_ session:URLSession, downloadTask:URLSessionDownloadTask, didWriteData bytesWritten:Int64,
                    totalBytesWritten:Int64, totalBytesExpectedToWrite:Int64) {
        if max(totalBytesWritten,totalBytesExpectedToWrite)>Int64(BookImport.maxBytes) { sizeExceeded=true; downloadTask.cancel(); return }
        progress(totalBytesExpectedToWrite>0 ? Double(totalBytesWritten)/Double(totalBytesExpectedToWrite) : nil)
    }
    func urlSession(_ session:URLSession, downloadTask:URLSessionDownloadTask, didFinishDownloadingTo location:URL) {
        do {
            guard let response=downloadTask.response as? HTTPURLResponse,(200..<300).contains(response.statusCode) else { throw ReaderFailure("Máy chủ chưa cung cấp được tệp sách.") }
            let bytes=try location.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard bytes<=BookImport.maxBytes else { throw ReaderFailure("Tệp sách vượt quá 200 MB.") }
            let saved=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            var name=response.suggestedFilename ?? input.lastPathComponent
            if (name as NSString).pathExtension.isEmpty && response.mimeType=="text/plain" { name += ".txt" }
            try FileManager.default.moveItem(at:location,to:saved)
            complete(.success((saved,name)),session)
        } catch { complete(.failure(error),session) }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        if let error { complete(.failure(sizeExceeded ? ReaderFailure("Tệp sách vượt quá 200 MB.") : error),session) }
    }
}
