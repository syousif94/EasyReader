//
//  Hash.swift
//  EasyReader
//
//  Created by Sammy Yousif on 11/10/25.
//

import Foundation
import CryptoKit

extension URL {
    func sha256Hash() -> String? {
        guard let data = try? Data(contentsOf: self) else {
            return nil
        }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // For large files, hash in chunks
    func sha256HashStreaming() -> String? {
        guard let inputStream = InputStream(url: self) else {
            return nil
        }
        
        inputStream.open()
        defer { inputStream.close() }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB chunks
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                hasher.update(data: Data(bytes: buffer, count: bytesRead))
            } else if bytesRead < 0 {
                return nil
            }
        }
        
        let hash = hasher.finalize()
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
