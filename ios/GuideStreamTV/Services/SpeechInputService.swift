//
//  SpeechInputService.swift
//  GuideStreamTV
//
//  Live speech-to-text dictation for the Stream Agent. Uses the Speech
//  framework with an AVAudioEngine tap so partial transcripts stream back
//  in real time while the user is speaking.
//

import Foundation
import Speech
import AVFoundation

/// Authorization state for the combined microphone + speech request.
enum SpeechAuthStatus {
    case authorized
    case denied
    case restricted
    case notDetermined
}

final class SpeechInputService {
    static let shared = SpeechInputService()

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?

    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    // MARK: - Authorization

    /// Combined authorization for speech recognition and microphone access.
    func requestAuthorization() async -> SpeechAuthStatus {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            switch speechStatus {
            case .denied: return .denied
            case .restricted: return .restricted
            default: return .notDetermined
            }
        }

        let micStatus = await withCheckedContinuation { (cont: CheckedContinuation<AVAudioSession.RecordPermission, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted ? .granted : .denied)
            }
        }

        return micStatus == .granted ? .authorized : .denied
    }

    // MARK: - Live recognition

    /// Starts streaming live speech recognition. Partial transcripts are
    /// delivered to `onPartial` on the main actor. Returns false if speech
    /// recognition is unavailable or already running.
    @discardableResult
    func start(onPartial: @escaping (String) -> Void) -> Bool {
        guard let speechRecognizer, speechRecognizer.isAvailable else { return false }
        guard !audioEngine.isRunning else { return false }

        // Reset any stale task.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 15.0, *) {
            request.addsPunctuation = true
        }
        request.taskHint = .search
        recognitionRequest = request

        let task = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in onPartial(transcript) }
            }
            if let error {
                // On a real recognition error, stop cleanly.
                Task { @MainActor in self?.stop() }
                _ = error
            }
        }
        recognitionTask = task

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            return false
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            inputNode.removeTap(onBus: 0)
            return false
        }
        return true
    }

    /// Stops recognition, removes the tap, and deactivates the audio session.
    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
