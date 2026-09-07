import CoreMedia
import Foundation
import ScreenCaptureKit

@available(macOS 13.0, *)
final class SpotifyAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let spotify = content.applications.first(where: {
            $0.bundleIdentifier == "com.spotify.client" || $0.applicationName.localizedCaseInsensitiveContains("Spotify")
        }) else {
            throw NSError(domain: "AirplayifyJam", code: 2, userInfo: [NSLocalizedDescriptionKey: "Spotify is not running"])
        }
        guard let display = content.displays.first else {
            throw NSError(domain: "AirplayifyJam", code: 3, userInfo: [NSLocalizedDescriptionKey: "No display is available for audio capture"])
        }

        let filter = SCContentFilter(display: display, including: [spotify], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2

        let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
        try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "airplayify.spotify.audio"))
        stream = capture
        try await capture.startCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              asbd.mBitsPerChannel == 32,
              (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 else { return }

        var listSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        let queryStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &listSize, bufferListOut: nil,
            bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil)
        guard queryStatus == noErr, listSize > 0 else {
            return
        }

        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: listSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawList.deallocate() }
        let list = rawList.assumingMemoryBound(to: AudioBufferList.self)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &listSize, bufferListOut: list,
            bufferListSize: listSize, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer)
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let frameCount = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        if buffers.count == 1, let data = buffers[0].mData {
            let byteCount = min(Int(buffers[0].mDataByteSize), frameCount * 2 * MemoryLayout<Float>.size)
            FileHandle.standardOutput.write(Data(bytes: data, count: byteCount))
            return
        }

        guard buffers.count >= 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        var interleaved = [Float](repeating: 0, count: frameCount * 2)
        for index in 0..<frameCount {
            interleaved[index * 2] = left[index]
            interleaved[index * 2 + 1] = right[index]
        }
        interleaved.withUnsafeBytes { bytes in
            FileHandle.standardOutput.write(Data(bytes: bytes.baseAddress!, count: bytes.count))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("Spotify capture stopped: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

@available(macOS 13.0, *)
@main
struct SpotifyCapture {
    static func main() async {
        if CommandLine.arguments.contains("--probe-permission") {
            await probePermission()
            return
        }
        do {
            let output = SpotifyAudioOutput()
            try await output.start()
            // `dispatchMain()` traps when called from Swift's async main
            // executor. Keep the async entrypoint alive without blocking the
            // executor; the capture object remains retained in this scope.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        } catch {
            fputs("Spotify capture unavailable: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func probePermission() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let spotifyRunning = content.applications.contains {
                $0.bundleIdentifier == "com.spotify.client" || $0.applicationName.localizedCaseInsensitiveContains("Spotify")
            }
            print("{\"capture\":\"authorized\",\"spotify\":\"\(spotifyRunning ? "running" : "not-running")\",\"display\":\"\(content.displays.isEmpty ? "missing" : "available")\"}")
        } catch {
            print("{\"capture\":\"denied\",\"spotify\":\"unknown\",\"display\":\"unknown\"}")
            exit(2)
        }
    }
}
