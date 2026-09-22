import Foundation
import GameRealtimeProtocolKit
import GameRealtimeStateKit

public struct DeterminismProfile: Codable, Hashable, Sendable {
    public let schemaID: String
    public let profileID: String
    public let byteOrder: String
    public let fixedPointScale: Int32
    public let stateHashAlgorithmID: String
    public let rngAlgorithmID: String

    public init(
        schemaID: String,
        profileID: String,
        byteOrder: String,
        fixedPointScale: Int32,
        stateHashAlgorithmID: String,
        rngAlgorithmID: String
    ) {
        self.schemaID = schemaID
        self.profileID = profileID
        self.byteOrder = byteOrder
        self.fixedPointScale = fixedPointScale
        self.stateHashAlgorithmID = stateHashAlgorithmID
        self.rngAlgorithmID = rngAlgorithmID
    }

    public static let v1 = DeterminismProfile(
        schemaID: "game-realtime-canonical-state-v1",
        profileID: "game-realtime-determinism-v1",
        byteOrder: "little-endian",
        fixedPointScale: 1_024,
        stateHashAlgorithmID: "fnv1a64-v1",
        rngAlgorithmID: "splitmix64-v1"
    )
}

public enum DeterminismProfileError: Error, Equatable, Sendable {
    case schemaIDMismatch(expected: String, actual: String)
    case profileIDMismatch(expected: String, actual: String)
    case byteOrderMismatch(expected: String, actual: String)
    case fixedPointScaleMismatch(expected: Int32, actual: Int32)
    case stateHashAlgorithmMismatch(expected: String, actual: String)
    case rngAlgorithmMismatch(expected: String, actual: String)
}

public enum RNGStreamID: UInt64, Codable, Sendable {
    case simulation = 1
    case combat = 2
}

public struct DeterministicRNG: Sendable {
    private static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15
    private static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9
    private static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB

    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= Self.increment
        return Self.mix(state)
    }

    public func stream(_ streamID: RNGStreamID) -> DeterministicRNG {
        let streamSalt = streamID.rawValue &* Self.increment
        return DeterministicRNG(seed: Self.mix(state ^ streamSalt))
    }

    private static func mix(_ input: UInt64) -> UInt64 {
        var value = input
        value = (value ^ (value >> 30)) &* firstMultiplier
        value = (value ^ (value >> 27)) &* secondMultiplier
        return value ^ (value >> 31)
    }
}

public enum SnapshotRestoreError: Error, Equatable, Sendable {
    case schemaMismatch(expected: String, actual: String)
    case profileMismatch(expected: String, actual: String)
    case deterministicStateHashMismatch(expected: UInt64, actual: UInt64)
    case malformedLengthPrefix(declared: Int, remaining: Int)
    case invalidOptionalPresenceByte(UInt8)
    case trailingCanonicalBytes(Int)
    case rngStreamOutOfOrder(previous: UInt64, current: UInt64)
    case duplicateRNGStreamID(UInt64)
    case unknownRNGStreamID(UInt64)
    case missingRNGStreamID(UInt64)
    case innerSchemaMismatch(expected: String, actual: String)
    case innerProfileMismatch(expected: String, actual: String)
    case innerProfileContractMismatch
    case snapshotMetadataMismatch
    case truncatedCanonicalBytes
    case invalidUTF8
    case corruptedCanonicalBytes
}

public struct CanonicalSnapshotCodec: Sendable {
    public let profile: DeterminismProfile

    public init(profile: DeterminismProfile) {
        self.profile = profile
    }

    public func encode(
        state: CanonicalWorldState,
        rng: [RNGStreamID: DeterministicRNG]
    ) throws -> CanonicalSnapshot {
        guard rng[.simulation] != nil else {
            throw SnapshotRestoreError.missingRNGStreamID(
                RNGStreamID.simulation.rawValue
            )
        }
        let sortedStreams = rng.keys.sorted {
            $0.rawValue < $1.rawValue
        }
        _ = try canonicalByteCount(streamCount: sortedStreams.count)
        try validateStandardV1Profile()

        var writer = CanonicalWriter(
            limit: RealtimeLimits.standardV1.canonicalSnapshotBytes
        )
        try writer.appendUTF8(profile.schemaID)
        try writer.appendUTF8(profile.profileID)
        try writer.appendUTF8(profile.byteOrder)
        try writer.appendInt32(profile.fixedPointScale)
        try writer.appendUTF8(profile.stateHashAlgorithmID)
        try writer.appendUTF8(profile.rngAlgorithmID)
        try writer.appendOptionalUTF8(nil)
        try writer.appendUInt64(state.tick)
        try writer.appendUInt64(state.epoch)
        try writer.appendUInt64(state.seed)
        try writer.appendUInt32(UInt32(sortedStreams.count))

        var streamSnapshots: [RNGStreamSnapshot] = []
        streamSnapshots.reserveCapacity(sortedStreams.count)
        for streamID in sortedStreams {
            guard let stream = rng[streamID] else {
                continue
            }
            try writer.appendUInt64(streamID.rawValue)
            try writer.appendUInt64(stream.state)
            streamSnapshots.append(
                RNGStreamSnapshot(
                    streamID: streamID.rawValue,
                    state: stream.state
                )
            )
        }

        let canonicalBytes = writer.data
        return try CanonicalSnapshot(
            schemaID: profile.schemaID,
            profileID: profile.profileID,
            tick: state.tick,
            epoch: state.epoch,
            rngStreams: streamSnapshots,
            canonicalBytes: canonicalBytes,
            deterministicStateHash: Self.fnv1a64(canonicalBytes)
        )
    }

    public func restore(
        _ snapshot: CanonicalSnapshot,
        state: inout CanonicalWorldState,
        rng: inout [RNGStreamID: DeterministicRNG]
    ) throws {
        try validateStandardV1Profile()
        guard snapshot.schemaID == profile.schemaID else {
            throw SnapshotRestoreError.schemaMismatch(
                expected: profile.schemaID,
                actual: snapshot.schemaID
            )
        }
        guard snapshot.profileID == profile.profileID else {
            throw SnapshotRestoreError.profileMismatch(
                expected: profile.profileID,
                actual: snapshot.profileID
            )
        }
        let actualHash = Self.fnv1a64(snapshot.canonicalBytes)
        guard actualHash == snapshot.deterministicStateHash else {
            throw SnapshotRestoreError.deterministicStateHashMismatch(
                expected: snapshot.deterministicStateHash,
                actual: actualHash
            )
        }

        let decoded = try decode(snapshot.canonicalBytes)
        guard decoded.schemaID == profile.schemaID else {
            throw SnapshotRestoreError.innerSchemaMismatch(
                expected: profile.schemaID,
                actual: decoded.schemaID
            )
        }
        guard decoded.profileID == profile.profileID else {
            throw SnapshotRestoreError.innerProfileMismatch(
                expected: profile.profileID,
                actual: decoded.profileID
            )
        }
        guard decoded.byteOrder == profile.byteOrder,
              decoded.fixedPointScale == profile.fixedPointScale,
              decoded.stateHashAlgorithmID == profile.stateHashAlgorithmID,
              decoded.rngAlgorithmID == profile.rngAlgorithmID
        else {
            throw SnapshotRestoreError.innerProfileContractMismatch
        }
        guard decoded.tick == snapshot.tick,
              decoded.epoch == snapshot.epoch,
              decoded.rngSnapshots == snapshot.rngStreams
        else {
            throw SnapshotRestoreError.snapshotMetadataMismatch
        }

        state = CanonicalWorldState(
            tick: decoded.tick,
            epoch: decoded.epoch,
            seed: decoded.seed
        )
        rng = decoded.rng
    }

    private func decode(_ data: Data) throws -> DecodedCanonicalState {
        var reader = CanonicalReader(data: data)
        let schemaID = try reader.readUTF8()
        let profileID = try reader.readUTF8()
        let byteOrder = try reader.readUTF8()
        let fixedPointScale = try reader.readInt32()
        let stateHashAlgorithmID = try reader.readUTF8()
        let rngAlgorithmID = try reader.readUTF8()
        guard try reader.readOptionalUTF8() == nil else {
            throw SnapshotRestoreError.innerProfileContractMismatch
        }
        let tick = try reader.readUInt64()
        let epoch = try reader.readUInt64()
        let seed = try reader.readUInt64()
        let streamCount = try reader.readUInt32()
        guard UInt64(streamCount) <= UInt64(reader.remainingByteCount / 16)
        else {
            throw SnapshotRestoreError.truncatedCanonicalBytes
        }

        var decodedRNG: [RNGStreamID: DeterministicRNG] = [:]
        decodedRNG.reserveCapacity(Int(streamCount))
        var streamSnapshots: [RNGStreamSnapshot] = []
        streamSnapshots.reserveCapacity(Int(streamCount))
        var previousStreamID: UInt64?
        for _ in 0 ..< streamCount {
            let rawStreamID = try reader.readUInt64()
            if let previousStreamID {
                if previousStreamID == rawStreamID {
                    throw SnapshotRestoreError.duplicateRNGStreamID(rawStreamID)
                }
                guard previousStreamID < rawStreamID else {
                    throw SnapshotRestoreError.rngStreamOutOfOrder(
                        previous: previousStreamID,
                        current: rawStreamID
                    )
                }
            }
            guard let streamID = RNGStreamID(rawValue: rawStreamID) else {
                throw SnapshotRestoreError.unknownRNGStreamID(rawStreamID)
            }
            let streamState = try reader.readUInt64()
            previousStreamID = rawStreamID
            decodedRNG[streamID] = DeterministicRNG(seed: streamState)
            streamSnapshots.append(
                RNGStreamSnapshot(
                    streamID: rawStreamID,
                    state: streamState
                )
            )
        }
        guard decodedRNG[.simulation] != nil else {
            throw SnapshotRestoreError.missingRNGStreamID(
                RNGStreamID.simulation.rawValue
            )
        }
        guard reader.isAtEnd else {
            throw SnapshotRestoreError.trailingCanonicalBytes(
                reader.remainingByteCount
            )
        }

        return DecodedCanonicalState(
            schemaID: schemaID,
            profileID: profileID,
            byteOrder: byteOrder,
            fixedPointScale: fixedPointScale,
            stateHashAlgorithmID: stateHashAlgorithmID,
            rngAlgorithmID: rngAlgorithmID,
            tick: tick,
            epoch: epoch,
            seed: seed,
            rng: decodedRNG,
            rngSnapshots: streamSnapshots
        )
    }

    private func validateStandardV1Profile() throws {
        let standard = DeterminismProfile.v1
        guard profile.schemaID == standard.schemaID else {
            throw DeterminismProfileError.schemaIDMismatch(
                expected: standard.schemaID,
                actual: profile.schemaID
            )
        }
        guard profile.profileID == standard.profileID else {
            throw DeterminismProfileError.profileIDMismatch(
                expected: standard.profileID,
                actual: profile.profileID
            )
        }
        guard profile.byteOrder == standard.byteOrder else {
            throw DeterminismProfileError.byteOrderMismatch(
                expected: standard.byteOrder,
                actual: profile.byteOrder
            )
        }
        guard profile.fixedPointScale == standard.fixedPointScale else {
            throw DeterminismProfileError.fixedPointScaleMismatch(
                expected: standard.fixedPointScale,
                actual: profile.fixedPointScale
            )
        }
        guard profile.stateHashAlgorithmID == standard.stateHashAlgorithmID
        else {
            throw DeterminismProfileError.stateHashAlgorithmMismatch(
                expected: standard.stateHashAlgorithmID,
                actual: profile.stateHashAlgorithmID
            )
        }
        guard profile.rngAlgorithmID == standard.rngAlgorithmID else {
            throw DeterminismProfileError.rngAlgorithmMismatch(
                expected: standard.rngAlgorithmID,
                actual: profile.rngAlgorithmID
            )
        }
    }

    private func canonicalByteCount(streamCount: Int) throws -> Int {
        let limit = RealtimeLimits.standardV1.canonicalSnapshotBytes
        var count = 0
        for string in [
            profile.schemaID,
            profile.profileID,
            profile.byteOrder,
            profile.stateHashAlgorithmID,
            profile.rngAlgorithmID,
        ] {
            count = try Self.addCanonicalByteCount(
                4,
                to: count,
                limit: limit
            )
            count = try Self.addCanonicalByteCount(
                string.utf8.count,
                to: count,
                limit: limit
            )
        }
        count = try Self.addCanonicalByteCount(4, to: count, limit: limit)
        count = try Self.addCanonicalByteCount(1, to: count, limit: limit)
        count = try Self.addCanonicalByteCount(28, to: count, limit: limit)
        let (streamBytes, streamOverflow) = streamCount.multipliedReportingOverflow(
            by: 16
        )
        guard !streamOverflow else {
            throw EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: limit,
                attempted: .max
            )
        }
        return try Self.addCanonicalByteCount(
            streamBytes,
            to: count,
            limit: limit
        )
    }

    private static func addCanonicalByteCount(
        _ additional: Int,
        to count: Int,
        limit: Int
    ) throws -> Int {
        let (attempted, overflow) = count.addingReportingOverflow(additional)
        guard !overflow, attempted <= limit else {
            throw EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: limit,
                attempted: overflow ? .max : attempted
            )
        }
        return attempted
    }

    private static func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private struct DecodedCanonicalState {
    let schemaID: String
    let profileID: String
    let byteOrder: String
    let fixedPointScale: Int32
    let stateHashAlgorithmID: String
    let rngAlgorithmID: String
    let tick: UInt64
    let epoch: UInt64
    let seed: UInt64
    let rng: [RNGStreamID: DeterministicRNG]
    let rngSnapshots: [RNGStreamSnapshot]
}

private struct CanonicalWriter {
    let limit: Int
    private(set) var data = Data()

    mutating func appendUInt8(_ value: UInt8) throws {
        try reserve(additionalByteCount: 1)
        data.append(value)
    }

    mutating func appendUInt32(_ value: UInt32) throws {
        try reserve(additionalByteCount: 4)
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func appendInt32(_ value: Int32) throws {
        try appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendUInt64(_ value: UInt64) throws {
        try reserve(additionalByteCount: 8)
        for shift in stride(from: 0, through: 56, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func appendUTF8(_ value: String) throws {
        let byteCount = value.utf8.count
        let (additionalByteCount, overflow) = byteCount.addingReportingOverflow(
            4
        )
        guard !overflow, byteCount <= Int(UInt32.max) else {
            throw EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: limit,
                attempted: .max
            )
        }
        try reserve(additionalByteCount: additionalByteCount)
        appendUInt32WithoutReservation(UInt32(byteCount))
        data.append(contentsOf: value.utf8)
    }

    mutating func appendOptionalUTF8(_ value: String?) throws {
        guard let value else {
            try appendUInt8(0)
            return
        }
        try appendUInt8(1)
        try appendUTF8(value)
    }

    private mutating func reserve(additionalByteCount: Int) throws {
        let (attempted, overflow) = data.count.addingReportingOverflow(
            additionalByteCount
        )
        guard !overflow, attempted <= limit else {
            throw EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: limit,
                attempted: overflow ? .max : attempted
            )
        }
    }

    private mutating func appendUInt32WithoutReservation(
        _ value: UInt32
    ) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }
}

private struct CanonicalReader {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool {
        offset == data.count
    }

    var remainingByteCount: Int {
        data.count - offset
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw SnapshotRestoreError.truncatedCanonicalBytes
        }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt32() throws -> UInt32 {
        guard remainingByteCount >= 4 else {
            throw SnapshotRestoreError.truncatedCanonicalBytes
        }
        var value: UInt32 = 0
        for shift in stride(from: 0, through: 24, by: 8) {
            value |= UInt32(data[offset]) << UInt32(shift)
            offset += 1
        }
        return value
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readUInt64() throws -> UInt64 {
        guard remainingByteCount >= 8 else {
            throw SnapshotRestoreError.truncatedCanonicalBytes
        }
        var value: UInt64 = 0
        for shift in stride(from: 0, through: 56, by: 8) {
            value |= UInt64(data[offset]) << UInt64(shift)
            offset += 1
        }
        return value
    }

    mutating func readUTF8() throws -> String {
        let byteCount = try readUInt32()
        guard UInt64(byteCount) <= UInt64(remainingByteCount) else {
            throw SnapshotRestoreError.malformedLengthPrefix(
                declared: Int(byteCount),
                remaining: remainingByteCount
            )
        }
        let end = offset + Int(byteCount)
        guard let value = String(
            data: data[offset ..< end],
            encoding: .utf8
        ) else {
            throw SnapshotRestoreError.invalidUTF8
        }
        offset = end
        return value
    }

    mutating func readOptionalUTF8() throws -> String? {
        switch try readUInt8() {
        case 0:
            return nil
        case 1:
            return try readUTF8()
        case let marker:
            throw SnapshotRestoreError.invalidOptionalPresenceByte(marker)
        }
    }
}
