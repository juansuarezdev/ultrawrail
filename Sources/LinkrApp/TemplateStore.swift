import Foundation
import LayoutEngine
import LinkrCore

struct TemplateStore {
    private let defaults = UserDefaults.standard
    private let key = "customTemplates"

    var templates: [Template] {
        get { defaults.data(forKey: key).map(TemplateCodec.decode) ?? [] }
        nonmutating set { defaults.set(TemplateCodec.encode(newValue), forKey: key) }
    }
}
