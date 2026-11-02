import UIKit
import AuthenticationServices
import CryptoKit
import Capacitor

// « Continuer avec Apple » et « Continuer avec Google » (02/11/2026). Le
// module renvoie le jeton d'identité signé par Apple ou Google ; la page le
// donne ensuite à Supabase (signInWithIdToken, voir js/connexionSociale.js).
// Google passe par la fenêtre de connexion sécurisée d'iOS, sans SDK Google
// (le module tout fait embarquait aussi le SDK Facebook).
@objc(ConnexionPlugin)
public class ConnexionPlugin: CAPPlugin, CAPBridgedPlugin, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    public let identifier = "ConnexionPlugin"
    public let jsName = "BligoConnexion"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "apple", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "google", returnType: CAPPluginReturnPromise)
    ]

    // Client « BliGO iPhone » du projet Google Cloud bligo-513513.
    static let googleClientId = "370561304576-ut61sg6i1ddkm8r2nvlodcc57de9ht9d.apps.googleusercontent.com"
    static let googleScheme = "com.googleusercontent.apps.370561304576-ut61sg6i1ddkm8r2nvlodcc57de9ht9d"

    private var appleCall: CAPPluginCall?
    private var webSession: ASWebAuthenticationSession?

    private var window: UIWindow {
        bridge?.viewController?.view.window ?? UIWindow()
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window }
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }

    // MARK: Apple

    @objc func apple(_ call: CAPPluginCall) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = call.getString("nonce")
        appleCall = call
        DispatchQueue.main.async {
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let call = appleCall else { return }
        appleCall = nil
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            call.reject("Connexion Apple impossible")
            return
        }
        // Prénom et nom : donnés par Apple seulement à la toute première connexion.
        // Le code d'autorisation sert à prévenir Apple quand le compte est
        // supprimé (fonction revoquer-apple).
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        call.resolve([
            "idToken": token,
            "authorizationCode": code,
            "givenName": credential.fullName?.givenName ?? "",
            "familyName": credential.fullName?.familyName ?? ""
        ])
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let call = appleCall else { return }
        appleCall = nil
        if (error as? ASAuthorizationError)?.code == .canceled {
            call.resolve(["cancelled": true])
        } else {
            call.reject(error.localizedDescription)
        }
    }

    // MARK: Google

    @objc func google(_ call: CAPPluginCall) {
        let verifier = Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
        let redirect = Self.googleScheme + ":/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.googleClientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: call.getString("nonce")),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        DispatchQueue.main.async {
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: Self.googleScheme) { url, error in
                self.webSession = nil
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        call.resolve(["cancelled": true])
                    } else {
                        call.reject(error.localizedDescription)
                    }
                    return
                }
                guard let url = url,
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                    call.reject("Connexion Google impossible")
                    return
                }
                Self.exchange(code: code, verifier: verifier, redirect: redirect, call: call)
            }
            session.presentationContextProvider = self
            self.webSession = session
            session.start()
        }
    }

    // Code reçu de Google -> jeton d'identité (PKCE, pas de secret pour un client iOS).
    private static func exchange(code: String, verifier: String, redirect: String, call: CAPPluginCall) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: googleClientId),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirect)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = json["id_token"] as? String else {
                call.reject(error?.localizedDescription ?? "Connexion Google impossible")
                return
            }
            call.resolve(["idToken": idToken])
        }.resume()
    }

    private static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL()
    }
}

private extension Data {
    func base64URL() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
