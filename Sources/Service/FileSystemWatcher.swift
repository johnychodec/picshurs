import Foundation
import os.log

final class FileSystemWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void
    private let logger = Logger(subsystem: "com.picshurs", category: "FileSystemWatcher")

    init(callback: @escaping ([String]) -> Void) {
        self.callback = callback
    }

    deinit {
        stop()
    }

    func watch(paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let cfPaths = paths as CFArray
        stream = FSEventStreamCreate(
            nil,
            { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                let changed = Array(paths.prefix(numEvents))
                watcher.callback(changed)
            },
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else {
            logger.error("Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        logger.info("FSEventStream started for \(paths.count) paths")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
