import UIKit
import Capacitor

// Thème clair / foncé de l'appli (28/10/2026). Entre deux pages, l'iPhone
// montre un instant le fond natif de l'écran : il suivait le réglage de
// l'iPhone (blanc en mode clair), d'où un flash blanc en thème foncé. Le
// choix fait dans le profil est donc aussi appliqué à l'écran natif, et gardé
// pour l'ouverture suivante de l'appli.
@objc(ApparencePlugin)
public class ApparencePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ApparencePlugin"
    public let jsName = "BligoApparence"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setTheme", returnType: CAPPluginReturnPromise)
    ]

    static let key = "bligo_apparence_fonce"

    // Même vert très foncé que le fond des pages (--sombre-fond dans
    // css/theme-sombre.css), pour qu'aucun noir ne clignote entre deux pages.
    static let fondFonce = UIColor(red: 0x1E / 255, green: 0x28 / 255, blue: 0x26 / 255, alpha: 1)

    static func apply(dark: Bool, to controller: UIViewController?) {
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        let fond = dark ? fondFonce : UIColor.white
        controller?.overrideUserInterfaceStyle = style
        controller?.view.window?.overrideUserInterfaceStyle = style
        controller?.view.backgroundColor = fond
        if let webView = (controller as? CAPBridgeViewController)?.webView {
            webView.backgroundColor = fond
            webView.scrollView.backgroundColor = fond
        }
    }

    @objc func setTheme(_ call: CAPPluginCall) {
        let dark = call.getBool("dark") ?? false
        UserDefaults.standard.set(dark, forKey: ApparencePlugin.key)
        DispatchQueue.main.async {
            ApparencePlugin.apply(dark: dark, to: self.bridge?.viewController)
            call.resolve()
        }
    }
}
