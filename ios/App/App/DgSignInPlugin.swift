import UIKit
import Capacitor
import AuthenticationServices
import CryptoKit

// Native sign-in on iOS (dg-apps#43). The browser detour (Safari View Controller -> login/app-*.html ->
// Firebase popup -> dhammagift:// back) did not come back on iOS for either provider, and even where it
// works it is an extra page with a second "Sign in with ..." button. Here:
//
//   apple()  — Sign in with Apple itself (ASAuthorizationController: the system sheet, Face ID). Returns the
//              identity token and the raw nonce whose SHA-256 went into the request; the page signs in to the
//              same Firebase account with OAuthProvider('apple.com').credential({ idToken, rawNonce }).
//              Needs the "Sign in with Apple" capability on the App ID and the matching entitlement.
//   google() — Google's OAuth 2.0 code flow with PKCE in ASWebAuthenticationSession: the system's own sign-in
//              sheet, which closes itself and returns straight to the app. This is what the GoogleSignIn SDK
//              does inside; without the SDK there is no package to add. clientId is an iOS OAuth client of
//              the Firebase project; its reversed form is the callback scheme. Returns the Google ID token.
@objc(DgSignInPlugin)
public class DgSignInPlugin: CAPPlugin, CAPBridgedPlugin, ASAuthorizationControllerDelegate,
                             ASAuthorizationControllerPresentationContextProviding,
                             ASWebAuthenticationPresentationContextProviding {
    public let identifier = "DgSignInPlugin"
    public let jsName = "DgSignIn"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "apple", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "google", returnType: CAPPluginReturnPromise)
    ]

    private var appleCall: CAPPluginCall?
    private var appleNonce = ""
    private var googleSession: ASWebAuthenticationSession?

    private static func randomToken(_ bytes: Int) -> String {
        var buffer = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buffer)
        return base64url(Data(buffer))
    }

    private static func base64url(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func anchor() -> ASPresentationAnchor {
        return bridge?.viewController?.view.window ?? ASPresentationAnchor()
    }

    // MARK: Apple

    @objc func apple(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let nonce = Self.randomToken(32)
            self.appleNonce = nonce
            self.appleCall = call
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    public func authorizationController(controller: ASAuthorizationController,
                                        didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { appleCall = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            appleCall?.reject("Apple returned no identity token", "credential")
            return
        }
        // The authorization code is what Apple's token revocation takes (account deletion, App Review
        // 5.1.1(v)): settings.js hands it to Firebase's accounts:revokeToken right before deleting.
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        appleCall?.resolve(["idToken": token, "rawNonce": appleNonce, "authorizationCode": code])
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // "cancelled" is the reader closing the sheet: the page stays quiet about it.
        let code = (error as? ASAuthorizationError)?.code == .canceled ? "cancelled" : "apple"
        appleCall?.reject(error.localizedDescription, code)
        appleCall = nil
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return anchor()
    }

    // MARK: Google

    @objc func google(_ call: CAPPluginCall) {
        guard let clientId = call.getString("clientId"), clientId.hasSuffix(".apps.googleusercontent.com") else {
            call.reject("clientId is missing", "config")
            return
        }
        let scheme = "com.googleusercontent.apps." + clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirect = scheme + ":/oauth2redirect"
        let verifier = Self.randomToken(48)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomToken(16)
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        DispatchQueue.main.async {
            let session = ASWebAuthenticationSession(url: auth.url!, callbackURLScheme: scheme) { url, error in
                self.googleSession = nil
                if let error = error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    call.reject(error.localizedDescription, cancelled ? "cancelled" : "google")
                    return
                }
                let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
                let value = { (name: String) in items.first(where: { $0.name == name })?.value }
                guard value("state") == state, let code = value("code") else {
                    call.reject("Google returned no authorization code (" + (value("error") ?? "unknown") + ")", "google")
                    return
                }
                Self.exchange(code: code, clientId: clientId, redirect: redirect, verifier: verifier, call: call)
            }
            session.presentationContextProvider = self
            self.googleSession = session
            if !session.start() { call.reject("the sign-in sheet could not start", "google") }
        }
    }

    // The code for tokens: an iOS client is a public client, so PKCE's verifier stands in for a secret.
    private static func exchange(code: String, clientId: String, redirect: String, verifier: String, call: CAPPluginCall) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = json["id_token"] as? String else {
                call.reject("Google token exchange failed" + (error.map { ": " + $0.localizedDescription } ?? ""), "google")
                return
            }
            call.resolve(["idToken": idToken])
        }.resume()
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return anchor()
    }
}
