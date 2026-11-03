import Foundation

/// Bounds the actual bytes read, even when the provider reports a false/missing file size.
enum BackupFileReader {
    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { localURL in
            result = Result { try readBounded(localURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw WalletError.invalid("无法读取所选备份，请确认文件已下载到本机。") }
        return try result.get()
    }
    private static func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw WalletError.invalid("请选择 JSON 备份文件。") }
        if let size = values.fileSize, size > BackupCodec.maxBytes { throw WalletError.invalid("备份超过 10MB，未读取或导入。") }
        guard let stream = InputStream(url: url) else { throw WalletError.invalid("无法打开备份文件。") }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count == 0 { return data }
            guard count > 0 else { throw stream.streamError ?? WalletError.invalid("备份文件读取失败。") }
            guard data.count + count <= BackupCodec.maxBytes else { throw WalletError.invalid("备份超过 10MB，未导入。") }
            data.append(buffer, count: count)
        }
    }
}
