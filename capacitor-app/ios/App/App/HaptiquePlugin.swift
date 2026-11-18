import UIKit
import AVFoundation
import Capacitor

// Retour du scan (18/11/2026, demande de Mégane : « biper avec le téléphone
// quand on scanne pour être sûr de le valider »). L'iPhone n'a pas
// navigator.vibrate : la vibration passe par ce module. La session audio est
// mise en lecture (mixée avec la musique éventuelle) pour que le bip du scan
// s'entende même avec le bouton silencieux de l'iPhone.
@objc(HaptiquePlugin)
public class HaptiquePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HaptiquePlugin"
    public let jsName = "BligoHaptique"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "vibrer", returnType: CAPPluginReturnPromise)
    ]

    static func preparerSon() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    @objc func vibrer(_ call: CAPPluginCall) {
        let refus = call.getString("type") == "refus"
        DispatchQueue.main.async {
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(refus ? .error : .success)
            call.resolve()
        }
    }
}
