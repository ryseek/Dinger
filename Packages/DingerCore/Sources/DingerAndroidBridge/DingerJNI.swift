#if canImport(Android)
import Android
import Dispatch
import DingerCore
import Foundation

private final class BlockingBox: @unchecked Sendable {
    var value = ""
}

private final class BridgeRuntime: @unchecked Sendable {
    static let shared = BridgeRuntime()

    private let stateLock = NSLock()
    private let callLock = NSLock()
    private var engine: DingerBridgeEngine?

    func open(path: String) -> String {
        callLock.lock()
        defer { callLock.unlock() }
        do {
            let opened = try DingerBridgeEngine(databasePath: path)
            stateLock.lock()
            engine = opened
            stateLock.unlock()
            return #"{"ok":true,"data":{"message":"DingerCore ready"}}"#
        } catch {
            return errorJSON(error.localizedDescription)
        }
    }

    func call(request: String) -> String {
        callLock.lock()
        defer { callLock.unlock() }
        stateLock.lock()
        let current = engine
        stateLock.unlock()
        guard let current else { return errorJSON("DingerCore is not initialized.") }

        let result = BlockingBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            result.value = await current.call(request)
            semaphore.signal()
        }
        semaphore.wait()
        return result.value
    }

    private func errorJSON(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return #"{"ok":false,"error":"\#(escaped)"}"#
    }
}

@_cdecl("Java_com_ryseek_dinger_core_DingerNative_open")
public func DingerNative_open(
    env: UnsafeMutablePointer<JNIEnv?>,
    clazz: jclass,
    path: jstring
) -> jstring {
    toJString(env, BridgeRuntime.shared.open(path: fromJString(env, path)))
}

@_cdecl("Java_com_ryseek_dinger_core_DingerNative_call")
public func DingerNative_call(
    env: UnsafeMutablePointer<JNIEnv?>,
    clazz: jclass,
    request: jstring
) -> jstring {
    toJString(env, BridgeRuntime.shared.call(request: fromJString(env, request)))
}

private func fromJString(_ env: UnsafeMutablePointer<JNIEnv?>, _ value: jstring) -> String {
    let length = Int(env.pointee!.pointee.GetStringLength(env, value))
    guard let pointer = env.pointee!.pointee.GetStringChars(env, value, nil) else { return "" }
    defer { env.pointee!.pointee.ReleaseStringChars(env, value, pointer) }
    return String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF16.self)
}

private func toJString(_ env: UnsafeMutablePointer<JNIEnv?>, _ value: String) -> jstring {
    let utf16 = Array(value.utf16)
    return utf16.withUnsafeBufferPointer { buffer in
        env.pointee!.pointee.NewString(env, buffer.baseAddress, jsize(buffer.count))!
    }
}
#else
import DingerCore

// Keeps the bridge product inspectable by host-side SwiftPM tooling. JNI
// entrypoints are compiled only by the Swift Android SDK.
public enum DingerAndroidBridgeAvailability {
    public static let isAvailable = false
}
#endif
