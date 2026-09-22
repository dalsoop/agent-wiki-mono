#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

struct GameDepthFileLock {
  let url: URL

  func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    guard flock(descriptor, LOCK_EX) == 0 else {
      close(descriptor)
      throw POSIXError(.EWOULDBLOCK)
    }
    defer {
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    return try operation()
  }
}
