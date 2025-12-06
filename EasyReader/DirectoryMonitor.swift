//
//  DirectoryMonitor.swift
//  EasyReader
//
//  Created by Sammy Yousif on 10/18/25.
//

import Foundation

protocol DirectoryMonitorDelegate: AnyObject {
    func directoryMonitor(directoryMonitor: DirectoryMonitor, didDetectChangeIn directoryURL: URL)
}

class DirectoryMonitor {
    weak var delegate: DirectoryMonitorDelegate?
    private let url: URL
    private let queue = DispatchQueue(label: "com.syousif.EasyReader.DirectoryMonitorQueue", attributes: .concurrent)

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init(url: URL) {
        self.url = url
    }

    func startMonitoring() {
        guard fileDescriptor == -1 && source == nil else { return } // Already monitoring

        // Open the directory for monitoring only
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open directory for monitoring.")
            return
        }

        // Create a dispatch source to monitor the directory
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write, // .write indicates directory content has changed
            queue: queue
        )

        // Set the event handler to notify the delegate of the change
        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.delegate?.directoryMonitor(directoryMonitor: self, didDetectChangeIn: self.url)
        }

        // Set the cancellation handler to close the file descriptor
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
            self.source = nil
        }

        source?.resume()
    }

    func stopMonitoring() {
        source?.cancel()
    }
    
    deinit {
        stopMonitoring()
    }
}
