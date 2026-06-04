import AVFoundation
import Foundation

struct RecordedAudio: Equatable {
    var data: Data
    var fileName: String
    var contentType: String
}

enum AudioRecordingPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unknown

    var canRecord: Bool {
        self == .authorized
    }

    var denialMessage: String? {
        switch self {
        case .authorized, .notDetermined:
            nil
        case .denied:
            "Microphone access is denied. Enable it in System Settings to record audio."
        case .restricted:
            "Microphone access is restricted on this Mac."
        case .unknown:
            "Microphone permission status is unknown."
        }
    }
}

protocol AudioRecordingControlling {
    func recordingPermissionStatus() -> AudioRecordingPermissionStatus
    func requestRecordingPermission() async -> AudioRecordingPermissionStatus
    func startRecording() async throws
    func stopRecording() async throws -> RecordedAudio
}

final class AVAudioRecordingController: AudioRecordingControlling {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func recordingPermissionStatus() -> AudioRecordingPermissionStatus {
        Self.mapAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestRecordingPermission() async -> AudioRecordingPermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                let status: AudioRecordingPermissionStatus = granted
                    ? .authorized
                    : Self.mapAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .audio))
                continuation.resume(returning: status)
            }
        }
    }

    func startRecording() async throws {
        guard recorder == nil else {
            throw AudioRecordingError.alreadyRecording
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-webui-native-recording-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AudioRecordingError.couldNotStart
        }

        self.recorder = recorder
        recordingURL = url
    }

    func stopRecording() async throws -> RecordedAudio {
        guard let recorder, let recordingURL else {
            throw AudioRecordingError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil

        let data = try Data(contentsOf: recordingURL)
        try? FileManager.default.removeItem(at: recordingURL)
        return RecordedAudio(
            data: data,
            fileName: "voice-recording-\(Self.timestampFormatter.string(from: Date())).m4a",
            contentType: "audio/mp4"
        )
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func mapAuthorizationStatus(_ status: AVAuthorizationStatus) -> AudioRecordingPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }
}

private enum AudioRecordingError: LocalizedError {
    case alreadyRecording
    case notRecording
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "Audio recording is already running."
        case .notRecording:
            "No audio recording is running."
        case .couldNotStart:
            "Audio recording could not start."
        }
    }
}
