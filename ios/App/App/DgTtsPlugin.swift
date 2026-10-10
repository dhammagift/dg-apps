import AVFoundation
import Capacitor

// Mirror of Android's DgTtsPlugin. Both exist for the same reason: the app's WebView has a Web
// Speech API that cannot speak. Android System WebView has no window.speechSynthesis at all; iOS
// WKWebView exposes one with ZERO voices and a speak() that never starts (measured in a simulator:
// voices=0, speaks=timeout), so the site's voice player (read/js/voice.js) found a synthesizer that
// silently did nothing. src/tts.js installs a Web-Speech-shaped shim over this plugin wherever the
// native API cannot speak.
//
//   speak({ id, text, lang, rate, voice })  -> resolves when queued; "tts" event {id, type:end|error}
//   cancel()                                 -> stops; no event, like Web Speech after onend=null
//   getVoices()                              -> { voices: [{ name, lang, localService }] }
//
// AVSpeechSynthesizer has no per-utterance id, so each utterance's id is kept here, keyed by the utterance
// itself, and every delegate callback is reported against its own utterance's id: the web side keys its
// pending utterances by id, and without this the player's "end" never arrives and its close button never
// closes (the exact Android bug this mirrors). One id for the whole plugin let a late didCancel of the
// phrase just stopped wipe the id of the phrase spoken right after it (the player skips with cancel +
// speak 50 ms later), and that phrase then ended with no "end".
//
// The audio session is activated by the first speak(), not at plugin load: activating it at load stopped
// the reader's music or podcast every time the app opened.
@objc(DgTtsPlugin)
public class DgTtsPlugin: CAPPlugin, CAPBridgedPlugin, AVSpeechSynthesizerDelegate {
    public let identifier = "DgTtsPlugin"
    public let jsName = "DgTts"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "speak", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getVoices", returnType: CAPPluginReturnPromise)
    ]

    private let synth = AVSpeechSynthesizer()
    // Main thread only: speak() hops there, and the delegate callbacks are handled there.
    private var ids: [ObjectIdentifier: String] = [:]

    override public func load() {
        synth.delegate = self
        // The app declares the audio background mode (Info.plist) so the reader keeps reading with the screen locked;
        // that needs the playback category. Only the category here: choosing it interrupts nobody. ACTIVATING it is what
        // stops other apps' sound, and that waits for the first phrase this plugin speaks (holdAudio).
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch {
            CAPLog.print("DgTts: audio session not configured: \(error.localizedDescription)")
        }
    }

    // Every phrase, not once: a phone call or another app may have taken the session since the last one.
    // ponytail: never deactivated - letting go between phrases would hand the sound back to other apps for the player's
    // 50 ms gaps, and WKWebView's own audio (the online voices) shares this session. Add a release on a long idle if
    // readers ask for their music back after listening.
    private func holdAudio() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            CAPLog.print("DgTts: audio session not activated: \(error.localizedDescription)")
        }
    }

    @objc func speak(_ call: CAPPluginCall) {
        guard let text = call.getString("text"), !text.isEmpty else {
            call.reject("no text to speak")
            return
        }

        let utterance = AVSpeechUtterance(string: text)

        // A named voice wins; otherwise the language decides. An unsupported language is REJECTED,
        // not silently ignored — that rejection is what lets the player fall back to the next
        // language on its list (pi -> sa -> en), the same contract Android's plugin implements.
        if let wanted = call.getString("voice"), !wanted.isEmpty, let voice = voice(named: wanted) {
            utterance.voice = voice
        } else if let lang = call.getString("lang"), !lang.isEmpty {
            guard let voice = AVSpeechSynthesisVoice(language: lang) else {
                call.reject("language not supported: \(lang)")
                return
            }
            utterance.voice = voice
        }

        // Web Speech's rate is 1.0 for normal speech and AVSpeechUtterance's default is 0.5, so the
        // two only agree if the requested rate is applied to the default rather than used raw.
        let rate = Float(call.getDouble("rate") ?? 1.0)
        let maxRate = Float(AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * rate, 0.0), maxRate)

        let id = call.getString("id") ?? ""
        DispatchQueue.main.async {
            self.holdAudio()
            self.ids[ObjectIdentifier(utterance)] = id
            self.synth.speak(utterance)
            call.resolve()
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.synth.stopSpeaking(at: .immediate)
            call.resolve()
        }
    }

    @objc func getVoices(_ call: CAPPluginCall) {
        let list = AVSpeechSynthesisVoice.speechVoices().map { voice -> [String: Any] in
            [
                "name": voice.name,
                "lang": voice.language,
                // Every voice iOS hands out is on the device; there is no network-backed engine to
                // report honestly here, and the player uses this to prefer offline voices.
                "localService": true
            ]
        }
        call.resolve(["voices": list])
    }

    private func voice(named name: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.name == name || $0.identifier == name }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // The utterance is captured, so it stays alive (and its identifier unique) until the main thread has run this.
        DispatchQueue.main.async {
            guard let id = self.ids.removeValue(forKey: ObjectIdentifier(utterance)) else { return }
            self.notifyListeners("tts", data: ["id": id, "type": "end"])
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // No event on purpose: a cancel is the caller's own doing, and Web Speech callers null their
        // handlers before cancelling (Android's plugin behaves the same way). Only THIS utterance's id goes.
        DispatchQueue.main.async {
            self.ids.removeValue(forKey: ObjectIdentifier(utterance))
        }
    }

    // No teardown hook: Capacitor 8's iOS CAPPlugin has no handleOnDestroy (Android's has one), and
    // the synthesizer dies with the plugin instance. A cancel is the only stop that matters.
}
