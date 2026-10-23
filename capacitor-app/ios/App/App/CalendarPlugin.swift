import UIKit
import EventKit
import EventKitUI
import Capacitor

// Ajout d'un événement de l'agenda culturel au calendrier de l'iPhone
// (23/10/2026). Ouvre la fenêtre d'Apple par-dessus l'appli, avec le détail
// de l'événement déjà rempli : l'usager choisit son agenda (iCloud, Google,
// Outlook... tous ceux du téléphone), touche « Ajouter » et reste dans BliGO.
// Depuis iOS 17, cette fenêtre ne demande aucune autorisation d'accès au
// calendrier ; avant iOS 17, l'autorisation est demandée une fois.
@objc(CalendarPlugin)
public class CalendarPlugin: CAPPlugin, CAPBridgedPlugin, EKEventEditViewDelegate {
    public let identifier = "CalendarPlugin"
    public let jsName = "BligoCalendar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "addEvent", returnType: CAPPluginReturnPromise)
    ]

    private let store = EKEventStore()
    private var pendingCall: CAPPluginCall?

    @objc func addEvent(_ call: CAPPluginCall) {
        guard let startMs = call.getDouble("start"), let endMs = call.getDouble("end") else {
            call.reject("Date de l'événement manquante")
            return
        }
        let present = {
            DispatchQueue.main.async {
                let event = EKEvent(eventStore: self.store)
                event.title = call.getString("title") ?? "Événement"
                event.location = call.getString("location")
                event.notes = call.getString("notes")
                event.startDate = Date(timeIntervalSince1970: startMs / 1000)
                event.endDate = Date(timeIntervalSince1970: endMs / 1000)

                let editor = EKEventEditViewController()
                editor.eventStore = self.store
                editor.event = event
                editor.editViewDelegate = self
                self.pendingCall = call
                self.bridge?.viewController?.present(editor, animated: true)
            }
        }
        if #available(iOS 17.0, *) {
            present()
        } else {
            store.requestAccess(to: .event) { granted, _ in
                if granted { present() } else { call.reject("Accès au calendrier refusé") }
            }
        }
    }

    public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        controller.dismiss(animated: true)
        pendingCall?.resolve(["added": action == .saved])
        pendingCall = nil
    }
}

// Écran principal de l'appli, avec le module calendrier ci-dessus enregistré.
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(CalendarPlugin())
    }
}
