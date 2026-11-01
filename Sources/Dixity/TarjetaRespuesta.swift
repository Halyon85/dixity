import AppKit
import SwiftUI

// La tarjeta de la respuesta (Preguntar, el menú del mouse, Claude y Codex). Cambia de forma según lo que muestra
// (Respuestas.Clase): texto con formato, traducción, texto leído, QR o link, uso de Claude y Codex. Abajo, los botones
// para seguir trabajando ("Pasar a inglés", "Más corto"…) y Copiar / Hacelo / Pegar. Vive dentro de la píldora.
struct TarjetaRespuesta: View {
    @ObservedObject var modelo: ModeloPildora
    let texto: String
    let tinta: Color
    let copiar: () -> Void
    let pegar: () -> Void
    let hacer: () -> Void
    let cerrar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    // Las capturas de prueba (Capturas.swift) dibujan sin esperar animaciones.
    static var sinAnimar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado
            if !modelo.miniaturas.isEmpty { miniaturas }
            cuerpo
                .id(texto)
                .transition(sinMovimiento ? .opacity : .opacity.combined(with: .offset(y: 6)))
            if let aviso = modelo.avisoTarjeta {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: modelo.avisoBueno ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(modelo.avisoBueno ? Tema.exito : Tema.acento)
                    Text(aviso).font(.system(size: 11.5)).foregroundStyle(tinta.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
            if let f = modelo.formato { filaFormatos(f) }
            if !modelo.opciones.isEmpty || modelo.puedeDeshacer { botonesSeguir }
            pie
        }
        .frame(width: 440)
    }

    // MARK: Encabezado

    private var estiloClase: (icono: String, color: Color) {
        switch modelo.clase {
        case .texto: ("sparkles", Tema.acento)
        case .traduccion: ("globe", Color(hex: 0x3B82F6))
        case .textoLeido: ("text.viewfinder", Color(hex: 0x14B8A6))
        case .codigos: ("qrcode", Tema.violeta)
        case .uso: ("gauge.with.dots.needle.50percent", Tema.exito)
        case .posteo: ("megaphone.fill", Color(hex: 0xEC4899))
        case .imagen: ("eye.fill", Color(hex: 0x6366F1))
        case .prompt: ("wand.and.stars", Color(hex: 0x8B5CF6))
        case .video: ("film", Color(hex: 0xEC4899))
        case .maqueta: ("rectangle.3.group.fill", Color(hex: 0xEC4899))
        case .colores: ("paintpalette.fill", Color(hex: 0xF59E0B))
        case .agente: (modelo.tituloRespuesta == "Codex" ? "chevron.left.forwardslash.chevron.right" : "terminal.fill",
                       modelo.tituloRespuesta == "Codex" ? Color(hex: 0x10A37F) : Color(hex: 0xD97757))
        }
    }

    // "Traductor de Apple · en la Mac" → "Traductor de Apple" y la marquita verde aparte.
    private var titulo: String {
        let t = modelo.tituloRespuesta.isEmpty ? T("Respuesta", "Answer") : modelo.tituloRespuesta
        return modelo.enLaMac ? String(t.components(separatedBy: " · ").first ?? t) : t
    }

    private var encabezado: some View {
        HStack(spacing: 8) {
            let e = estiloClase
            Image(systemName: e.icono).font(.system(size: 11, weight: .semibold)).foregroundStyle(e.color)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(e.color.opacity(0.16)))
            Text(titulo).font(.system(size: 13, weight: .semibold))
            if modelo.enLaMac {
                HStack(spacing: 3) {
                    Image(systemName: "leaf.fill").font(.system(size: 8.5, weight: .bold))
                    Text(T("Gratis · en la Mac", "Free · on your Mac")).font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(Tema.exito.opacity(0.14)))
                .foregroundStyle(Tema.exito)
                .help(T("Se resolvió en tu Mac: no usó IA ni internet.", "Done on your Mac: no AI, no internet."))
            }
            Spacer(minLength: 12)
            Button(action: cerrar) {
                HStack(spacing: 4) {
                    Text("Esc").font(.system(size: 10, weight: .medium)).opacity(0.45)
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).opacity(0.6)
                }
                .frame(height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(T("Cerrar", "Close"))
        }
    }

    // La imagen que miró la IA, chiquita: así se ve de qué habla la respuesta. Una sola, con su forma (hasta 200 de
    // ancho); varias, en cuadraditos.
    private var miniaturas: some View {
        HStack(spacing: 6) {
            let unaSola = modelo.miniaturas.count == 1
            ForEach(Array(modelo.miniaturas.prefix(5).enumerated()), id: \.offset) { _, img in
                let forma = img.size.height > 0 ? img.size.width / img.size.height : 1
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: unaSola ? min(200, max(48, 64 * forma)) : 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tinta.opacity(0.12), lineWidth: 0.75))
            }
        }
        .transition(.opacity)
    }

    // MARK: Cuerpo según la clase

    @ViewBuilder private var cuerpo: some View {
        let trabajando = modelo.trabajando
        ZStack {
            Group {
                switch modelo.clase {
                case .uso(let usos):
                    VistaUso(usos: usos, tinta: tinta)
                case .posteo:
                    VistaPosteo(texto: texto, tinta: tinta)
                case .codigos:
                    VistaCodigos(texto: texto, tinta: tinta)
                case .traduccion(let de, let a, let original):
                    VistaTraduccion(texto: texto, de: de, a: a, original: original, tinta: tinta)
                case .textoLeido, .prompt, .video:
                    Desplazable { TextoConFormato(texto: texto, tinta: tinta) }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tinta.opacity(0.05)))
                case .colores:
                    VistaColores(texto: texto, tinta: tinta)
                case .texto, .agente, .imagen, .maqueta:
                    Desplazable { TextoConFormato(texto: texto, tinta: tinta) }
                }
            }
            .opacity(trabajando == nil ? 1 : 0)
            .blur(radius: trabajando == nil || sinMovimiento ? 0 : 2)
            if let o = trabajando {
                HStack(spacing: 7) {
                    Image(systemName: o.icono).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.acento)
                    Brillo(texto: o.trabajando, color: tinta)
                }
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(tinta.opacity(0.07)))
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .overlay {
            if trabajando != nil && !sinMovimiento {
                BordeGirando(forma: RoundedRectangle(cornerRadius: 10, style: .continuous), color: Tema.acento)
                    .padding(-6)
            }
        }
    }

    // MARK: Botones para seguir

    // Para qué es la imagen: cambia el final del prompt al instante (proporción y tamaño de Instagram o YouTube).
    private func filaFormatos(_ elegido: Respuestas.Formato) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "aspectratio").font(.system(size: 11, weight: .semibold)).opacity(0.45)
                .help(T("Formato de la imagen", "Image format"))
            HStack(spacing: 2) {
                ForEach(Respuestas.Formato.allCases, id: \.self) { f in
                    ChipFormato(nombre: f.corto, ayuda: f.ayuda, elegido: f == elegido, tinta: tinta, espacio: espacioFormato,
                                apagado: modelo.trabajando != nil) { modelo.alFormato(f) }
                }
            }
            .padding(2)
            .background(Capsule().fill(tinta.opacity(0.06)))
        }
    }
    @Namespace private var espacioFormato

    private var botonesSeguir: some View {
        VStack(alignment: .leading, spacing: 6) {
        if let pregunta = modelo.preguntaOpciones {
            Text(pregunta).font(.system(size: 11.5, weight: .semibold)).opacity(0.75)
                .transition(.opacity)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if modelo.puedeDeshacer {
                    BotonSeguir(icono: "arrow.uturn.backward", nombre: T("Deshacer", "Undo"), gratis: false, tinta: tinta,
                                apagado: modelo.trabajando != nil) { modelo.alDeshacer() }
                }
                ForEach(modelo.opciones, id: \.self) { o in
                    BotonSeguir(icono: o.icono, nombre: o.nombre, gratis: o.enLaMac, tinta: tinta,
                                apagado: modelo.trabajando != nil, ayuda: o.sinIA && !o.enLaMac ? "" : nil) { modelo.alOpcion(o) }
                }
            }
            .padding(.vertical, 1).padding(.horizontal, 1)
        }
        }
    }

    // MARK: Pie

    private var detalle: String {
        switch modelo.clase {
        case .uso, .codigos, .posteo, .colores: return ""
        default:
            let n = Respuestas.palabras(texto)
            var partes = [n == 1 ? T("1 palabra", "1 word") : T("\(n) palabras", "\(n) words")]
            if n > 2, let i = Respuestas.idioma(de: texto) { partes.append(Respuestas.nombreIdioma(i).capitalized) }
            return partes.joined(separator: " · ")
        }
    }

    private var pie: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if !detalle.isEmpty { Text(detalle).font(.system(size: 10.5, weight: .medium)).opacity(0.45) }
                if !modelo.atajoPreguntar.isEmpty && modelo.hacelo == nil && modelo.clase != .colores {   // colores no se ajustan
                    Text(T("Mantené \(modelo.atajoPreguntar) para ajustarla", "Hold \(modelo.atajoPreguntar) to adjust it"))
                        .font(.system(size: 10.5)).opacity(0.4)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: copiar) {
                HStack(spacing: 5) {
                    Image(systemName: modelo.copiado ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(modelo.copiado ? T("Copiado", "Copied") : T("Copiar", "Copy")).font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(tinta.opacity(0.1)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            if let hacelo = modelo.hacelo {
                // Edita archivos del proyecto: solo con un clic, nunca con ↩.
                Button(action: hacer) {
                    HStack(spacing: 5) {
                        Image(systemName: "hammer.fill").font(.system(size: 10, weight: .semibold))
                        Text(hacelo).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(Tema.acento.opacity(0.15)))
                    .foregroundStyle(Tema.acento)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if modelo.puedePegar {
                Button(action: pegar) {
                    HStack(spacing: 5) {
                        Text(T("Pegar", "Paste")).font(.system(size: 12, weight: .semibold))
                        Image(systemName: "return").font(.system(size: 10, weight: .bold)).opacity(0.85)
                    }
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(Tema.acento))
                    .foregroundStyle(.white)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Un botón chico para seguir trabajando. Los que se hacen gratis en la Mac llevan un puntito verde.
private struct BotonSeguir: View {
    let icono: String
    let nombre: String
    let gratis: Bool
    let tinta: Color
    let apagado: Bool
    var ayuda: String? = nil      // "": sin cartelito (Volver, Copiar imagen); nil: el de siempre (gratis o tu IA)
    let accion: () -> Void
    @Estado private var encima = false

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                Image(systemName: icono).font(.system(size: 10, weight: .semibold))
                Text(nombre).font(.system(size: 11.5, weight: .medium))
                if gratis { Circle().fill(Tema.exito).frame(width: 5, height: 5) }
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(encima ? Tema.acento.opacity(0.14) : tinta.opacity(0.06)))
            .overlay(Capsule().strokeBorder(encima ? Tema.acento.opacity(0.35) : tinta.opacity(0.09), lineWidth: 1))
            .foregroundStyle(encima ? Tema.acento : tinta.opacity(0.85))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(apagado)
        .opacity(apagado ? 0.45 : 1)
        .onHover { e in withAnimation(.easeOut(duration: 0.12)) { encima = e } }
        .help(ayuda ?? (gratis ? T("Gratis: lo hace el traductor de Apple, en tu Mac (si el idioma está bajado).",
                                   "Free: Apple Translate does it on your Mac (if the language is downloaded).")
                               : T("Usa tu IA.", "Uses your AI.")))
    }
}

// Un formato de la fila (Original, Post 4:5…): el elegido lleva la marca, que se desliza al cambiar.
private struct ChipFormato: View {
    let nombre: String
    let ayuda: String
    let elegido: Bool
    let tinta: Color
    let espacio: Namespace.ID
    let apagado: Bool
    let accion: () -> Void
    @Estado private var encima = false

    var body: some View {
        Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { accion() } }) {
            Text(nombre).font(.system(size: 11, weight: elegido ? .semibold : .medium))
                .padding(.horizontal, 9).frame(height: 22)
                .foregroundStyle(elegido ? Tema.acento : tinta.opacity(encima ? 0.9 : 0.6))
                .background {
                    if elegido {
                        Capsule().fill(Tema.acento.opacity(0.16))
                            .overlay(Capsule().strokeBorder(Tema.acento.opacity(0.3), lineWidth: 1))
                            .matchedGeometryEffect(id: "formato", in: espacio)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(apagado)
        .onHover { e in withAnimation(.easeOut(duration: 0.12)) { encima = e } }
        .help(ayuda + T(" Siempre en alta resolución.", " Always high resolution."))
    }
}

// Los colores de lo elegido: una muestra por color con su código y cuánto ocupa. Clic en una copia su código; Copiar,
// abajo, los copia todos. El texto viene como "#1E1B3A · 42 %", uno por renglón.
private struct VistaColores: View {
    let texto: String
    let tinta: Color
    @Estado private var copiado: String?

    private var colores: [(hex: String, parte: String)] {
        texto.split(separator: "\n").compactMap { l in
            let partes = l.components(separatedBy: " · ")
            guard let hex = partes.first, hex.hasPrefix("#"), hex.count == 7 else { return nil }
            return (hex, partes.count > 1 ? partes[1] : "")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(colores, id: \.hex) { c in
                let valor = UInt32(c.hex.dropFirst(), radix: 16) ?? 0
                Button {
                    Cursor.copiar(c.hex)
                    withAnimation(.easeOut(duration: 0.15)) { copiado = c.hex }
                } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: valor))
                            .frame(width: 56, height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tinta.opacity(0.14), lineWidth: 0.75))
                            .overlay {
                                if copiado == c.hex {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.4), radius: 2).transition(.scale.combined(with: .opacity))
                                }
                            }
                        Text(c.hex).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).opacity(0.8)
                        Text(c.parte).font(.system(size: 9.5)).opacity(0.45)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(T("Copiar \(c.hex)", "Copy \(c.hex)"))
            }
            Spacer(minLength: 0)
        }
    }
}

// Lo largo se recorre con barra; lo corto ocupa lo justo.
private struct Desplazable<C: View>: View {
    @ViewBuilder let contenido: C
    var body: some View {
        ScrollView {
            contenido.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Texto con formato

private struct TextoConFormato: View {
    let texto: String
    let tinta: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(Respuestas.bloques(texto).enumerated()), id: \.offset) { _, b in
                switch b {
                case .parrafo(let t):
                    Text(Self.conMarcas(t)).font(.system(size: 13.5)).lineSpacing(2)
                case .titulo(let t):
                    Text(Self.conMarcas(t)).font(.system(size: 14, weight: .semibold)).padding(.top, 2)
                case .item(let marca, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(marca).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tema.acento).frame(minWidth: 14, alignment: .trailing)
                        Text(Self.conMarcas(t)).font(.system(size: 13.5)).lineSpacing(2)
                    }
                case .codigo(let c):
                    BloqueCodigo(codigo: c, tinta: tinta)
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    // **negrita**, *cursiva* y `código` dentro del texto; si no se puede leer, el texto tal cual.
    static func conMarcas(_ t: String) -> AttributedString {
        (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
    }
}

private struct BloqueCodigo: View {
    let codigo: String
    let tinta: Color
    @Estado private var copiado = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(codigo).font(.system(size: 12, design: .monospaced)).lineSpacing(2)
                .padding(10).padding(.trailing, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tinta.opacity(0.07)))
            Button {
                Cursor.copiar(codigo)
                withAnimation(Tema.expo) { copiado = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(Tema.expo) { copiado = false } }
            } label: {
                Image(systemName: copiado ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
                    .foregroundStyle(copiado ? Tema.exito : tinta.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
            .help(T("Copiar este bloque", "Copy this block"))
        }
    }
}

// MARK: Traducción

private struct VistaTraduccion: View {
    let texto: String
    let de: String
    let a: String
    let original: String
    let tinta: Color
    @Estado private var verOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(Respuestas.nombreIdioma(de).capitalized).opacity(0.6)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: 0x3B82F6))
                Text(Respuestas.nombreIdioma(a).capitalized).foregroundStyle(Color(hex: 0x3B82F6))
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9).frame(height: 22)
            .background(Capsule().fill(Color(hex: 0x3B82F6).opacity(0.1)))
            Desplazable { TextoConFormato(texto: texto, tinta: tinta) }
            if !original.isEmpty {
                Button {
                    withAnimation(Tema.expo) { verOriginal.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(verOriginal ? 90 : 0))
                        Text(T("Ver el original", "Show original")).font(.system(size: 11, weight: .medium))
                    }
                    .opacity(0.55).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if verOriginal {
                    Text(original).font(.system(size: 12.5)).lineSpacing(2).opacity(0.6).lineLimit(8).textSelection(.enabled)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Capsule().fill(tinta.opacity(0.15)).frame(width: 2) }
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
        }
    }
}

// MARK: QR y links

private struct VistaCodigos: View {
    let texto: String
    let tinta: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(texto.components(separatedBy: "\n").filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, linea in
                if let url = Respuestas.links(linea).first, Respuestas.links(linea).count == 1 {
                    FilaLink(url: url, tinta: tinta)
                } else {
                    Text(linea).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tinta.opacity(0.05)))
                }
            }
        }
    }
}

// Un link leído de un QR: el dominio grande para ver a dónde lleva, y Abrir solo con clic (nunca se abre solo).
private struct FilaLink: View {
    let url: URL
    let tinta: Color
    private var seguro: Bool { url.scheme?.lowercased() == "https" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: seguro ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(seguro ? Tema.exito : Color(hex: 0xF5A524))
                .frame(width: 28, height: 28)
                .background(Circle().fill((seguro ? Tema.exito : Color(hex: 0xF5A524)).opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(url.host() ?? url.absoluteString).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(seguro ? url.absoluteString : T("Sin https: puede no ser seguro · ", "No https: may not be safe · ") + url.absoluteString)
                    .font(.system(size: 11)).opacity(0.55).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 4) {
                    Text(T("Abrir", "Open")).font(.system(size: 12, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.system(size: 9.5, weight: .bold))
                }
                .padding(.horizontal, 11).frame(height: 26)
                .background(Capsule().fill(Tema.violeta.opacity(0.15)))
                .foregroundStyle(Tema.violeta)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tinta.opacity(0.05)))
    }
}

// MARK: Posteos

// Una pestaña por red (LinkedIn, Instagram, X, Plan…), cada una con su Copiar y el contador contra el límite de la red.
private struct VistaPosteo: View {
    let texto: String
    let tinta: Color
    @Estado private var elegida = 0
    @Estado private var copiado = false
    @Namespace private var espacio
    private let rosa = Color(hex: 0xEC4899)

    var body: some View {
        let secciones = Posteos.secciones(texto)
        if secciones.isEmpty {
            Desplazable { TextoConFormato(texto: texto, tinta: tinta) }
        } else {
            let i = min(elegida, secciones.count - 1)
            let s = secciones[i]
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(secciones.enumerated()), id: \.offset) { j, sec in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { elegida = j; copiado = false }
                            } label: {
                                Text(sec.titulo).font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 11).frame(height: 26)
                                    .background {
                                        if j == i { Capsule().fill(rosa.opacity(0.16)).matchedGeometryEffect(id: "pestaña", in: espacio) }
                                    }
                                    .foregroundStyle(j == i ? rosa : tinta.opacity(0.6))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Capsule().fill(tinta.opacity(0.05)))
                }
                Desplazable { TextoConFormato(texto: s.texto, tinta: tinta) }
                    .id(i)
                    .transition(.opacity)
                HStack(spacing: 8) {
                    if let limite = s.limite {
                        let largo = s.texto.count
                        HStack(spacing: 6) {
                            ProgressView(value: Double(min(largo, limite)), total: Double(limite))
                                .progressViewStyle(.linear).tint(largo > limite ? Tema.error : rosa).frame(width: 70)
                            Text("\(largo) / \(limite)").font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                                .foregroundStyle(largo > limite ? Tema.error : tinta.opacity(0.5))
                        }
                        .help(T("Caracteres contra el límite de \(s.titulo).", "Characters against \(s.titulo)'s limit."))
                    }
                    Spacer()
                    Button {
                        Cursor.copiar(s.texto)
                        withAnimation(Tema.expo) { copiado = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiado ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                            Text(copiado ? T("Copiado", "Copied") : T("Copiar \(s.titulo)", "Copy \(s.titulo)"))
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(rosa.opacity(0.14)))
                        .foregroundStyle(rosa)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: Uso de Claude y Codex

private struct VistaUso: View {
    let usos: [Agentes.Uso]
    let tinta: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(usos.enumerated()), id: \.offset) { i, u in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: u.agente == .claude ? "terminal.fill" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(u.agente == .claude ? Color(hex: 0xD97757) : Color(hex: 0x10A37F))
                        Text(u.agente.nombre).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if let l = u.leido { Text(Self.hace(l)).font(.system(size: 10.5)).opacity(0.45) }
                    }
                    if u.topes.isEmpty {
                        Text(T("No informó cuánto usaste.", "Didn't report your usage.")).font(.system(size: 12)).opacity(0.6)
                    }
                    ForEach(Array(u.topes.enumerated()), id: \.offset) { j, t in
                        BarraUso(tope: t, tinta: tinta, retraso: Double(i * 2 + j) * 0.09)
                    }
                    if !u.hoy.isEmpty {
                        HStack(spacing: 5) {
                            Text(T("Hoy", "Today")).font(.system(size: 11, weight: .semibold)).opacity(0.5)
                            ForEach(u.hoy, id: \.proyecto) { s in
                                HStack(spacing: 3) {
                                    Text(s.proyecto).lineLimit(1)
                                    Text("\(s.cantidad)").fontWeight(.bold).monospacedDigit()
                                }
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 7).frame(height: 19)
                                .background(Capsule().fill(tinta.opacity(0.07)))
                            }
                        }
                        .help(T("Conversaciones de Claude Code de hoy, por proyecto.", "Today's Claude Code conversations, by project."))
                    }
                }
                if i < usos.count - 1 { Divider().opacity(0.5) }
            }
        }
    }

    static func hace(_ fecha: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: T("es_AR", "en_US"))
        f.unitsStyle = .short
        return T("Dato \(f.localizedString(for: fecha, relativeTo: Date()))", "As of \(f.localizedString(for: fecha, relativeTo: Date()))")
    }
}

// Una barra: se llena al aparecer, verde hasta el 70 %, ámbar hasta el 90 % y roja después.
private struct BarraUso: View {
    let tope: Agentes.Uso.Tope
    let tinta: Color
    let retraso: Double
    @Estado private var lleno = TarjetaRespuesta.sinAnimar
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    private var color: Color { tope.usado >= 90 ? Tema.error : tope.usado >= 70 ? Color(hex: 0xF5A524) : Tema.exito }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(tope.nombre).font(.system(size: 12, weight: .medium)).opacity(0.8)
                Spacer()
                Text("\(tope.usado) %").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(tinta.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(7, g.size.width * CGFloat(lleno ? min(100, max(0, tope.usado)) : 0) / 100))
                        .shadow(color: color.opacity(0.35), radius: 3, y: 0)
                }
            }
            .frame(height: 7)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                HStack {
                    Text(T("Te queda \(max(0, 100 - tope.usado)) %", "\(max(0, 100 - tope.usado)) % left"))
                    Spacer()
                    if let r = tope.renueva { Text(Respuestas.cuentaRegresiva(hasta: r, desde: ctx.date)) }
                }
                .font(.system(size: 10.5)).opacity(0.55)
            }
        }
        .onAppear {
            guard !lleno else { return }
            if sinMovimiento { lleno = true; return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.12 + retraso)) { lleno = true }
        }
    }
}
