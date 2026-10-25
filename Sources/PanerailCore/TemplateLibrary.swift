import Foundation
import LayoutEngine

public enum TemplateCodec {
    public static func encode(_ templates: [Template]) -> Data? {
        try? JSONEncoder().encode(templates)
    }

    /// Decodes each element on its own so one corrupt entry cannot wipe the rest.
    private struct Lossy: Decodable {
        let value: Template?
        init(from decoder: Decoder) throws { value = try? Template(from: decoder) }
    }

    /// Nil when the data is not a JSON array at all (nothing could be decoded).
    public static func decodeIfPossible(_ data: Data) -> [Template]? {
        (try? JSONDecoder().decode([Lossy].self, from: data))?.compactMap(\.value)
    }

    /// Decodes stored templates. Anything invalid is dropped; widths are normalized to sum to 1.
    public static func decode(_ data: Data) -> [Template] {
        guard let stored = decodeIfPossible(data) else { return [] }
        let builtInIds = Set(Template.builtIn.map(\.id))
        var seen = Set<String>()
        var result: [Template] = []
        for template in stored {
            guard !template.columns.isEmpty,
                  template.columns.allSatisfy({ $0.width > 0 && (1...TemplateDraft.maxSlots).contains($0.slots) }),
                  template.columns.count <= TemplateDraft.maxColumns,
                  !builtInIds.contains(template.id),
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
