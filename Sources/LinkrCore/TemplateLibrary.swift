import Foundation
import LayoutEngine

public enum TemplateCodec {
    public static func encode(_ templates: [Template]) -> Data? {
        try? JSONEncoder().encode(templates)
    }

    /// Decodes stored templates. Anything invalid is dropped; widths are normalized to sum to 1.
    public static func decode(_ data: Data) -> [Template] {
        guard let stored = try? JSONDecoder().decode([Template].self, from: data) else { return [] }
        var seen = Set<String>()
        var result: [Template] = []
        for template in stored {
            guard !template.columns.isEmpty,
                  template.columns.allSatisfy({ $0.width > 0 && (1...TemplateDraft.maxSlots).contains($0.slots) }),
                  template.columns.count <= TemplateDraft.maxColumns,
                  seen.insert(template.id).inserted else { continue }
            let draft = TemplateDraft(columns: template.columns)
            result.append(Template(id: template.id, name: template.name, columns: draft.columns))
        }
        return result
    }
}

public enum TemplateLibrary {
    /// Built-in templates first, then the custom ones whose id does not clash with a built-in.
    public static func all(custom: [Template]) -> [Template] {
        let builtInIds = Set(Template.builtIn.map(\.id))
        return Template.builtIn + custom.filter { !builtInIds.contains($0.id) }
    }
}
