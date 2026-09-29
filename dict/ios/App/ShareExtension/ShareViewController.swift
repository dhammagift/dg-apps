import UIKit
import WebKit

// The Share Extension: text or a link shared from another app is looked up right here in the sheet —
// dict.dhamma.gift itself, since this app (unlike the reader) has no offline library or bundled pages
// of its own to fall back on; it is a live-site wrapper on every ordinary launch too.
//
// It cannot hand the text to the containing app instead and let THAT open dict.dhamma.gift: a share
// extension is a separate process living inside someone else's sheet, and opening its own app is
// reserved for Today and iMessage extensions — the documentation for NSExtensionContext.open names
// those two and no others (see the main app's own ShareViewController.swift for the four ways that
// was tried and rejected). So, same as there: the extension does the work itself.
class ShareViewController: UIViewController {

    private var webView: WKWebView!
    private let status = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        webView = WKWebView(frame: .zero)

        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)

        status.text = "Searching…"
        status.textAlignment = .center
        status.textColor = .secondaryLabel

        for child in [done, webView!, status] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }

        NSLayoutConstraint.activate([
            done.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            webView.topAnchor.constraint(equalTo: done.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        status.numberOfLines = 0
        webView.navigationDelegate = self
        webView.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sharedText { [weak self] text in
            guard let self = self else { return }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let payload = trimmed, !payload.isEmpty else {
                self.status.text = "Nothing to search for: the share carried no text or link."
                return
            }
            self.search(for: payload)
        }
    }

    // The first usable attachment: plain text, or a URL (the site's own `?q=` handling also
    // understands a shared link — it is a search for that link's text).
    private func sharedText(completion: @escaping (String?) -> Void) {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        guard !attachments.isEmpty else {
            completion(nil)
            return
        }

        func firstString(from providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
            guard let provider = providers.first else {
                completion(nil)
                return
            }
            let rest = Array(providers.dropFirst())

            func handle(_ identifier: String) -> Bool {
                guard provider.hasItemConformingToTypeIdentifier(identifier) else { return false }
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                    var text = item as? String
                    if text == nil, let url = item as? URL { text = url.absoluteString }
                    if text == nil, let attributed = item as? NSAttributedString { text = attributed.string }
                    if text == nil, let data = item as? Data { text = String(data: data, encoding: .utf8) }
                    DispatchQueue.main.async {
                        if let text = text, !text.isEmpty { completion(text) } else { firstString(from: rest, completion: completion) }
                    }
                }
                return true
            }

            if handle("public.plain-text") { return }
            if handle("public.url") { return }
            firstString(from: rest, completion: completion)
        }

        firstString(from: attachments, completion: completion)
    }

    private func search(for payload: String) {
        // ponytail: the query rides in the URL, which has a practical ceiling of a few kilobytes. A
        // whole page pasted into a share is beyond it; for a word, a phrase or a link — what people
        // actually share — this is enough, and the ceiling is named rather than silently dropping
        // the tail.
        let capped = payload.count > 4000 ? String(payload.prefix(4000)) : payload
        guard let encoded = capped.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dict.dhamma.gift/?q=" + encoded) else {
            status.text = "That text could not be turned into a search."
            return
        }
        webView.load(URLRequest(url: url))
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

extension ShareViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        status.isHidden = true
        webView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status.text = "The page could not be loaded: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status.text = "The page could not be loaded: \(error.localizedDescription)"
    }
}
