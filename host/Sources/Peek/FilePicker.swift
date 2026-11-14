import UIKit
import UniformTypeIdentifiers

/// Presents the system document picker for a single file.
///
/// UIKit is used directly, through the initializer without `asCopy`, because hosts such as
/// LiveContainer intercept the other initializers (and SwiftUI's `fileImporter`) and turn the
/// picker into a folder picker in which files cannot be tapped.
@MainActor
final class FilePicker: NSObject, UIDocumentPickerDelegate {
    private var completion: ((URL?) -> Void)?

    func present(types: [UTType], completion: @escaping (URL?) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else {
            completion(nil)
            return
        }
        while let presented = top.presentedViewController { top = presented }
        self.completion = completion
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion?(urls.first)
        completion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion = nil
    }
}
