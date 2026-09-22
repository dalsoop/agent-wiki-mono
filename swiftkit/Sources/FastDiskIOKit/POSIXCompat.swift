#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum POSIXCompat {
    static func mtimeSec(_ st: stat) -> Int {
        #if canImport(Darwin)
        Int(st.st_mtimespec.tv_sec)
        #else
        Int(st.st_mtim.tv_sec)
        #endif
    }

    static func mtimeNsec(_ st: stat) -> Int {
        #if canImport(Darwin)
        Int(st.st_mtimespec.tv_nsec)
        #else
        Int(st.st_mtim.tv_nsec)
        #endif
    }

    static func direntName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafePointer(to: &entry.pointee.d_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }
    }
}
