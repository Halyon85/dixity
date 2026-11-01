import AppKit
import ApplicationServices

// Aprender de lo que corregís a mano: un rato después de pegar un dictado se vuelve a leer el campo y, si cambiaste
// un nombre por otro que suena parecido ("Dick City" → "Dixity"), se sugiere sumarlo al diccionario con ese alias.
// Solo sugiere (decidís vos en Diccionario): un alias cambia lo que dijiste antes de la IA (auditoría del 23/10/2026).
// Necesita "Mirar la ventana" prendido, nunca mira un campo de contraseña y no guarda lo que leyó.
final class Correcciones {
    static let shared = Correcciones()
    // Lecturas después de pegar, en segundos. Un cambio cuenta cuando dos lecturas seguidas dan lo mismo: así no se
    // toma una palabra a medio escribir.
    static let lecturas: [Double] = [6, 12, 20, 32]
    private var vuelta = 0   // sube con cada pegado: el pegado nuevo deja sin efecto la vigilancia del anterior

    // Lo llama Motor.entregar cuando un dictado entró en el campo.
    func vigilar(pegado: String) {
        vuelta += 1
        let n = vuelta
        guard Ajustes.shared.datos.mirarVentana, pegado.count <= 2_000,
              let campo = Cursor.campoEnfocado(), campo.valor.utf16.count <= 20_000,
              let r = campo.valor.range(of: pegado, options: .backwards) else { return }
        let antes = String(campo.valor[..<r.lowerBound]), despues = String(campo.valor[r.upperBound...])
        var anterior: String?
        for espera in Self.lecturas {
            DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in
                guard let self, self.vuelta == n else { return }
                // Cambió fuera de lo pegado (lo mandaste, lo borraste o el campo es otro): se deja.
                guard let ahora = Cursor.valor(de: campo.elemento),
                      let medio = Self.medio(antes: antes, despues: despues, ahora: ahora) else { self.vuelta += 1; return }
                defer { anterior = medio }
                guard medio != pegado, medio == anterior else { return }
                self.vuelta += 1
                let cambios = Self.cambios(pegado: pegado, corregido: medio)
                if !cambios.isEmpty { Sugerencias.shared.aprenderCorreccion(cambios) }
            }
        }
    }

    // Lo que quedó en el lugar de lo pegado, si lo de antes y lo de después siguen iguales.
    static func medio(antes: String, despues: String, ahora: String) -> String? {
        guard ahora.count >= antes.count + despues.count, ahora.hasPrefix(antes), ahora.hasSuffix(despues) else { return nil }
        return String(ahora.dropFirst(antes.count).dropLast(despues.count))
    }

    // Nombres que cambiaste por otro parecido: (cómo quedó, cómo lo había escrito). Nada si reescribiste mucho
    // (eso ya no es corregir una palabra) ni si el cambio fue de sentido ("martes" → "jueves") o una palabra común.
    static func cambios(pegado: String, corregido: String) -> [(nuevo: String, viejo: String)] {
        let viejo = palabras(pegado), nuevo = palabras(corregido)
        guard !viejo.isEmpty, viejo.count <= 400, nuevo.count <= 600 else { return [] }
        let bloques = diferencias(viejo.map(\.normal), nuevo.map(\.normal))
        let tocadas = bloques.reduce(0) { $0 + $1.viejo.count }
        guard !bloques.isEmpty, tocadas <= max(3, viejo.count * 2 / 5) else { return [] }
        var r: [(nuevo: String, viejo: String)] = []
        for b in bloques where (1...3).contains(b.viejo.count) && (1...3).contains(b.nuevo.count) {
            let texto = b.nuevo.map { nuevo[$0].texto }.joined(separator: " ")
            let dicho = b.viejo.map { viejo[$0].normal }.joined(separator: " ")
            let a = dicho.replacingOccurrences(of: " ", with: ""), z = Diccionario.normalizar(texto).replacingOccurrences(of: " ", with: "")
            guard a != z, texto.count >= 3, texto.count <= 40, !Secretos.pareceSecreto(texto) else { continue }
            let parecido = 1 - Double(Diccionario.distancia(Array(a), Array(z))) / Double(max(a.count, z.count))
            guard parecido >= 0.5 else { continue }
            // A principio de oración la mayúscula no dice nada: ahí vale si juntaste palabras ("dick city" → "Dixity").
            let inicio = b.nuevo.first.map { $0 == 0 || nuevo[$0 - 1].cierra } ?? true
            let pareceNombre = b.nuevo.contains { Sugerencias.pareceTermino(nuevo[$0].texto, inicioDeOracion: inicio) }
            guard pareceNombre || (inicio && b.viejo.count > b.nuevo.count) else { continue }
            r.append((texto, dicho))
        }
        return Array(r.prefix(3))
    }

    private struct Palabra { let texto: String; let normal: String; let cierra: Bool }

    private static func palabras(_ s: String) -> [Palabra] {
        s.split(whereSeparator: \.isWhitespace).compactMap { bruto in
            let t = String(bruto).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            let n = Diccionario.normalizar(t)
            return n.isEmpty ? nil : Palabra(texto: t, normal: n, cierra: bruto.last.map { ".!?".contains($0) } ?? false)
        }
    }

    // Tramos distintos entre las dos listas (índices de cada una), según la subsecuencia común más larga.
    private static func diferencias(_ a: [String], _ b: [String]) -> [(viejo: [Int], nuevo: [Int])] {
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var r: [(viejo: [Int], nuevo: [Int])] = []
        var i = 0, j = 0, va: [Int] = [], vb: [Int] = []
        func cerrar() { if !va.isEmpty || !vb.isEmpty { r.append((va, vb)) }; va = []; vb = [] }
        while i < a.count || j < b.count {
            if i < a.count && j < b.count && a[i] == b[j] { cerrar(); i += 1; j += 1 }
            else if j < b.count && (i == a.count || t[i][j + 1] >= t[i + 1][j]) { vb.append(j); j += 1 }
            else { va.append(i); i += 1 }
        }
        cerrar()
        return r
    }
}
