import Foundation

// Contexto del proyecto en el que estás trabajando, para el modo Trabajo.
// Busca qué proyecto aparece en el título de la ventana (Terminal, Claude, Cursor muestran la carpeta)
// y lee su guía (AGENTS.md / CLAUDE.md) y los nombres de sus archivos principales.
struct ContextoProyecto {
    var nombre: String
    var guia: String
    var nombres: [String]
}

enum Proyectos {
    private static var cache: [String: (Date, ContextoProyecto)] = [:]
    private static let cola = DispatchQueue(label: "dixity.proyectos")

    // Cada carpeta configurada puede ser un proyecto o una carpeta que contiene proyectos.
    static func candidatos(_ carpetas: [String]) -> [URL] {
        let fm = FileManager.default
        var lista: [URL] = []
        for c in carpetas where !c.isEmpty {
            let u = URL(fileURLWithPath: (c as NSString).expandingTildeInPath, isDirectory: true)
            guard fm.fileExists(atPath: u.path) else { continue }
            lista.append(u)
            let hijos = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            lista += hijos.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        return lista
    }

    // El proyecto cuyo nombre de carpeta aparece en la ventana o cerca del cursor (gana el nombre más largo).
    static func detectar(_ c: ContextoCursor?, carpetas: [String]) -> URL? {
        guard let c else { return nil }
        let texto = (c.ventana + " " + c.antes.suffix(300)).lowercased()
        guard !texto.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return candidatos(carpetas)
            .filter { $0.lastPathComponent.count >= 4 && texto.contains($0.lastPathComponent.lowercased()) }
            .max { $0.lastPathComponent.count < $1.lastPathComponent.count }
    }

    static func contexto(de carpeta: URL) -> ContextoProyecto {
        cola.sync {
            if let (fecha, ctx) = cache[carpeta.path], Date().timeIntervalSince(fecha) < 600 { return ctx }
            let ctx = leer(carpeta)
            cache[carpeta.path] = (Date(), ctx)
            return ctx
        }
    }

    private static func leer(_ carpeta: URL) -> ContextoProyecto {
        let fm = FileManager.default
        var guia = ""
        for nombre in ["AGENTS.md", "CLAUDE.md", "LEEME.md", "README.md"] {
            guard var t = leerDentro(nombre, de: carpeta) else { continue }
            // CLAUDE.md a veces solo dice "@AGENTS.md": seguimos el enlace, pero solo a otro archivo del proyecto.
            if t.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@"),
               let destino = t.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first?.dropFirst(),
               let t2 = leerDentro(String(destino).trimmingCharacters(in: .whitespaces), de: carpeta) {
                t = t2
            }
            if t.count > 80 { guia = String(t.prefix(3500)); break }
        }
        let ignorar: Set<String> = ["node_modules", "build", "dist", "Build", "Pods", "DerivedData", "venv"]
        let nombres = ((try? fm.contentsOfDirectory(atPath: carpeta.path)) ?? [])
            .filter { !$0.hasPrefix(".") && !ignorar.contains($0) }
            .sorted()
            .prefix(60)
        return ContextoProyecto(nombre: carpeta.lastPathComponent, guia: guia, nombres: Array(nombres))
    }

    // Lee una guía del proyecto solo si es un archivo común (no un enlace) que queda adentro de la carpeta, y como
    // mucho 16 KB. La guía viene de repositorios ajenos: antes "@../../.ssh/id_rsa" o un AGENTS.md que era un enlace
    // hacían leer cualquier archivo de la Mac y mandarlo a la IA (auditoría de seguridad del 23/10/2026).
    static func leerDentro(_ relativa: String, de carpeta: URL) -> String? {
        let partes = relativa.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativa.isEmpty, !relativa.hasPrefix("/"), !relativa.hasPrefix("~"),
              !partes.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        let u = carpeta.appendingPathComponent(relativa)
        let base = carpeta.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard u.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base),
              let v = try? u.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
              v.isSymbolicLink == false, v.isRegularFile == true,
              let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        guard let datos = try? h.read(upToCount: 16 * 1024) else { return nil }
        return String(decoding: datos, as: UTF8.self)
    }
}
