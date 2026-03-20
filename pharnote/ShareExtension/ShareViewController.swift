import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let sharedStore = PharnoteSharedIncomingDocumentStore()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let statusLabel = UILabel()
    private var didStartProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartProcessing else { return }
        didStartProcessing = true
        processIncomingShare()
    }

    private func configureLayout() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.text = "PharNote로 여는 중..."

        view.addSubview(activityIndicator)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func processIncomingShare() {
        guard let provider = firstFileProvider() else {
            finish(withErrorMessage: "공유된 파일을 찾을 수 없습니다.")
            return
        }

        let preferredTypes = [
            UTType.pdf.identifier,
            UTType.image.identifier,
            UTType.data.identifier
        ]

        loadFileURL(from: provider, preferredTypes: preferredTypes) { [weak self] url, errorMessage in
            guard let self else { return }
            guard let url else {
                self.finish(withErrorMessage: errorMessage ?? "공유된 파일을 읽을 수 없습니다.")
                return
            }

            do {
                let reference = try self.sharedStore.persistIncomingFile(from: url)
                self.openHostApp(with: reference)
            } catch {
                self.finish(withErrorMessage: error.localizedDescription)
            }
        }
    }

    private func firstFileProvider() -> NSItemProvider? {
        for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
                    provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                    provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    return provider
                }
            }
        }
        return nil
    }

    private func loadFileURL(
        from provider: NSItemProvider,
        preferredTypes: [String],
        completion: @escaping (URL?, String?) -> Void
    ) {
        let typeIdentifier = preferredTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) ?? preferredTypes.first

        guard let typeIdentifier else {
            completion(nil, "지원하지 않는 파일 형식입니다.")
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            if let url {
                completion(url, nil)
                return
            }

            if let error {
                completion(nil, error.localizedDescription)
                return
            }

            completion(nil, "파일 URL을 생성하지 못했습니다.")
        }
    }

    private func openHostApp(with reference: PharnoteIncomingShareReference) {
        guard let openURL = PharnoteShareImportURL(token: reference.token).makeURL() else {
            finish(withErrorMessage: "앱 열기 URL을 만들 수 없습니다.")
            return
        }

        extensionContext?.open(openURL) { [weak self] _ in
            self?.finish()
        }
    }

    private func finish(withErrorMessage message: String? = nil) {
        DispatchQueue.main.async {
            if let message {
                self.statusLabel.text = message
                self.activityIndicator.stopAnimating()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.extensionContext?.cancelRequest(withError: NSError(
                        domain: "PharnoteShareExtension",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    ))
                }
                return
            }

            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
