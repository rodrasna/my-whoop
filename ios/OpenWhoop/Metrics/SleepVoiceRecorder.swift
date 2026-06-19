import AVFoundation
import Foundation
import Speech

// MARK: - SleepVoiceRecorder
// Transcripción en vivo con Speech framework (es-ES).

@MainActor
final class SleepVoiceRecorder: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var partialTranscript = ""
    @Published private(set) var finalTranscript = ""

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    func requestPermissions() async -> Bool {
        let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        guard mic else { return false }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func toggleRecording() async {
        if isRecording {
            stopRecording()
            return
        }
        await startRecording()
    }

    private func startRecording() async {
        finalTranscript = ""
        partialTranscript = ""

        guard await requestPermissions() else {
            phase = .failed("Necesitamos permiso de micrófono y reconocimiento de voz.")
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            phase = .failed("Reconocimiento de voz no disponible en este dispositivo.")
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            phase = .failed("No se pudo activar el audio.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalTranscript = text
                        self.partialTranscript = text
                    } else {
                        self.partialTranscript = text
                    }
                }
                if error != nil, self.finalTranscript.isEmpty, !self.partialTranscript.isEmpty {
                    self.finalTranscript = self.partialTranscript
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            phase = .recording
        } catch {
            phase = .failed("No se pudo iniciar la grabación.")
            teardownAudio()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        phase = .processing
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        if finalTranscript.isEmpty, !partialTranscript.isEmpty {
            finalTranscript = partialTranscript
        }
        teardownAudio()
        phase = .idle
    }

    private func teardownAudio() {
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
