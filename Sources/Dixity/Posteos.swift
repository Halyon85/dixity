import Foundation

// Postear con tus carpetas: "armame un post para LinkedIn sobre Dixity" o "el plan de contenidos de la semana para
// Café Luna". Dixity busca la marca en tus Carpetas de marca y marketing (Modos › Proyectos) y el producto en tus
// Carpetas de proyectos, y se lo pasa a Claude Code en la carpeta de marketing, solo leyendo y con tu suscripción.
// La respuesta llega en una tarjeta con una pestaña por red. Nunca publica nada: "Guardar borrador" (Hacelo) deja el
// texto en la carpeta de la marca, y publicar sigue siendo tuyo.
enum Posteos {
    struct Marca: Equatable {
        var nombre: String
        var carpeta: URL      // la de la marca (marcas/<marca>), o la carpeta entera si no hay marcas adentro
        var raiz: URL         // la carpeta de marketing que elegiste: ahí trabaja Claude (lee su AGENTS.md)
    }

    // ¿Es un pedido de posteo? Palabras de redes y contenidos, en pedidos de hasta 40 palabras.
    static func esPedido(_ pedido: String) -> Bool {
        let p = " " + Diccionario.normalizar(pedido) + " "
        guard p.split(separator: " ").count <= 40 else { return false }
        let claves = [" post ", " posts ", " posteo", " postear", " publicacion", " plan de contenido", " calendario de contenido",
                      " carrusel", " campana para", " reel ", " copy para", " caption", " hilo para x", " tweet"]
        let redes = [" para linkedin", " para instagram", " para x ", " para tiktok", " para facebook", " en linkedin", " en instagram"]
        return claves.contains { p.contains($0) } || redes.contains { p.contains($0) }
    }

    // Las marcas de tus carpetas: si una tiene "marcas/", cada subcarpeta es una; si no, la carpeta es la marca.
    static func marcas(en carpetas: [String]) -> [Marca] {
        let fm = FileManager.default
        var lista: [Marca] = []
        for c in carpetas where !c.isEmpty {
            let raiz = URL(fileURLWithPath: (c as NSString).expandingTildeInPath, isDirectory: true)
            let dir = raiz.appendingPathComponent("marcas", isDirectory: true)
            let hijas = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            if hijas.isEmpty {
                if fm.fileExists(atPath: raiz.path) { lista.append(Marca(nombre: raiz.lastPathComponent, carpeta: raiz, raiz: raiz)) }
            } else {
                lista += hijas.map { Marca(nombre: $0.lastPathComponent, carpeta: $0, raiz: raiz) }
            }
        }
        return lista
    }

    // La marca que nombraste (gana el nombre más largo). Si hay una sola, esa. Si no se sabe, nil (y se pregunta).
    static func elegir(_ pedido: String, marcas: [Marca]) -> Marca? {
        let p = " " + Diccionario.normalizar(pedido) + " "
        let nombrada = marcas.filter { p.contains(" " + Diccionario.normalizar($0.nombre) + " ") }
            .max { $0.nombre.count < $1.nombre.count }
        if let nombrada { return nombrada }
        if marcas.count == 1 { return marcas.first }
        return nil
    }

    // El proyecto del producto que nombraste: por el nombre de la carpeta o por el título de su README ("# Dixity").
    static func producto(_ pedido: String, carpetas: [String]) -> URL? {
        let p = " " + Diccionario.normalizar(pedido) + " "
        var mejor: (URL, Int)?
        for u in Proyectos.candidatos(carpetas) {
            var nombres = [u.lastPathComponent]
            if let readme = Proyectos.leerDentro("README.md", de: u),
               let titulo = readme.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
                nombres.append(String(titulo.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            for n in nombres where n.count >= 4 && p.contains(" " + Diccionario.normalizar(n) + " ") {
                if n.count > (mejor?.1 ?? 0) { mejor = (u, n.count) }
            }
        }
        return mejor?.0
    }

    // Cómo tiene que responder Claude: secciones "## <Red>" (la tarjeta las pone en pestañas) y nada de publicar.
    static func guia(_ m: Marca, producto: URL?) -> (leer: String, hacer: String) {
        let ficha = m.carpeta == m.raiz ? "" : T(" Leé primero la guía de esa carpeta (AGENTS.md o HANDOFF.md) y la ficha de la marca en \(m.carpeta.path) (INDICE.md, README.md o marca.json).",
                                                 " First read that folder's guide (AGENTS.md or HANDOFF.md) and the brand's files in \(m.carpeta.path) (INDICE.md, README.md or marca.json).")
        let prod = producto.map { T(" Para saber qué es el producto, mirá su README o manual en \($0.path).", " To learn what the product is, read its README or manual in \($0.path).") } ?? ""
        let leer = T("Te habla una persona por voz desde Dixity, una app de dictado. Quiere contenido para redes de la marca \(m.nombre).\(ficha)\(prod) Respetá el tono, lo que la marca dice y lo que no dice. Respondé en español rioplatense (o en el idioma que pida) con una sección por red, cada una con un título de la forma «## LinkedIn», «## Instagram» o «## X», y adentro solo el texto listo para copiar y pegar, con sus hashtags. Si pide un plan, sumá una sección «## Plan» con un día por línea. Al final, una sección «## Imagen» con una idea de imagen o video. No escribas nada antes de la primera sección. No publiques ni mandes nada.",
                     "A person is talking to you by voice from Dixity, a dictation app. They want social content for the brand \(m.nombre).\(ficha)\(prod) Keep the brand's tone and what it does and doesn't say. Reply with one section per network, each titled like “## LinkedIn”, “## Instagram” or “## X”, containing only the copy-ready text with its hashtags. If they ask for a plan, add a “## Plan” section with one day per line. At the end, an “## Image” section with an image or video idea. Write nothing before the first section. Don't publish or send anything.")
        let organico = m.carpeta == m.raiz ? m.raiz.path : m.carpeta.appendingPathComponent("organico").path
        let hacer = T("Guardá estos borradores tal cual, en un archivo Markdown nuevo dentro de \(organico) (con la fecha de hoy en el nombre). No toques ningún otro archivo, no publiques y no mandes nada. Al terminar, decí en una línea dónde quedó.",
                      "Save these drafts as they are, in a new Markdown file inside \(organico) (with today's date in the name). Don't touch any other file, don't publish and don't send anything. When done, say in one line where it is.")
        return (leer, hacer)
    }

    // MARK: La tarjeta

    struct Seccion: Equatable {
        var titulo: String
        var texto: String
        // Hasta cuántos caracteres admite cada red (para el contador de la tarjeta). nil: sin límite.
        var limite: Int? {
            switch Diccionario.normalizar(titulo) {
            case "x", "twitter": 280
            case "linkedin": 3000
            case "instagram", "facebook", "tiktok": 2200
            case "threads": 500
            default: nil
            }
        }
    }

    // Las secciones "## Título" de la respuesta. Lo que venga antes de la primera queda como "Nota".
    static func secciones(_ texto: String) -> [Seccion] {
        var lista: [Seccion] = []
        var actual: Seccion?
        var antes: [String] = []
        for linea in texto.components(separatedBy: "\n") {
            if linea.hasPrefix("## ") {
                if let a = actual { lista.append(a) }
                actual = Seccion(titulo: String(linea.dropFirst(3)).trimmingCharacters(in: .whitespaces), texto: "")
            } else if actual != nil {
                actual!.texto += (actual!.texto.isEmpty ? "" : "\n") + linea
            } else {
                antes.append(linea)
            }
        }
        if let a = actual { lista.append(a) }
        let nota = antes.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !nota.isEmpty { lista.insert(Seccion(titulo: T("Nota", "Note"), texto: nota), at: 0) }
        return lista.map { Seccion(titulo: $0.titulo, texto: $0.texto.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.texto.isEmpty }
    }
}
