import Foundation
import LayoutEngine
import LinkrCore

struct TemplateStore {
    private let defaults = UserDefaults.standard
    private let key = "customTemplates"

    var templates: [Template] {
        get { defaults.data(forKey: key).map(TemplateCodec.decode) ?? [] }
        nonmutating set {
            // Never overwrite stored data we could not read, and never write nil (that deletes the key).
            if let stored = defaults.data(forKey: key), TemplateCodec.decodeIfPossible(stored) == nil { return }
            guard let data = TemplateCodec.encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }
}
