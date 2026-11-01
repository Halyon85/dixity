import AppKit
import ImageIO
import SwiftUI

// Historial del portapapeles: textos, imágenes y archivos copiados en las últimas 24 horas.
// Las contraseñas no se guardan: los gestores las marcan como "ocultas" y esas se saltean.
struct ElementoCopiado: Codable, Identifiable, Equatable {
    enum Tipo: String, Codable { case texto, imagen, archivos }
    var id = UUID()
    var fecha = Date()
    var tipo: Tipo
    var texto: String? = nil
    var imagen: String? = nil          // PNG en Dicta/Portapapeles
    var archivos: [String]? = nil      // rutas
    var app: String? = nil

    var resumen: String {
        switch tipo {
        case .texto: return texto ?? ""
        case .imagen: return T("Imagen", "Image")
        case .archivos:
            let n = archivos?.count ?? 0
            return n == 1 ? (archivos?.first.map { ($0 as NSString).lastPathComponent } ?? T("Archivo", "File")) : T("\(n) archivos", "\(n) files")
        }
    }
}

final class Portapapeles: ObservableObject {
    static let shared = Portapapeles()
    static let horas: Double = 24
    static let maximo = 200
    static let carpeta: URL = {
        let u = Almacen.carpeta.appendingPathComponent("Portapapeles", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    // Marcas de "no guardar" (todas las conocidas, también las viejas que respetan otros gestores del portapapeles).
    private static var ocultos: Set<String> { Secretos.marcasPrivadas }

    @Published private(set) var elementos: [ElementoCopiado]
    private var ultimoCambio = NSPasteboard.general.changeCount
    private var reloj: Timer?
    private var poda: Timer?

    private init() {
        elementos = Almacen.leer([ElementoCopiado].self, "portapapeles.json") ?? []
        podar()
    }

    func arrancar() {
        guard reloj == nil else { return }
        ultimoCambio = NSPasteboard.general.changeCount
        reloj = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in self?.revisar() }
        reloj?.tolerance = 0.25
        poda = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.podar() }
    }

    func detener() { reloj?.invalidate(); reloj = nil; poda?.invalidate(); poda = nil }

    private func revisar() {
        let pb = NSPasteboard.general
        guard pb.changeCount != ultimoCambio else { return }
        ultimoCambio = pb.changeCount
        if Cursor.cambiosPropios.contains(pb.changeCount) { return }   // lo escribió Dicta
        let tipos = Set((pb.types ?? []).map(\.rawValue))
        guard tipos.isDisjoint(with: Portapapeles.ocultos) else { return }
        // Lo que se copia con un gestor de contraseñas adelante no se guarda aunque no traiga marca.
        if Secretos.esGestor(NSWorkspace.shared.frontmostApplication) { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            sumar(ElementoCopiado(tipo: .archivos, archivos: urls.map(\.path), app: app))
        } else if let datos = pb.data(forType: .png) ?? pb.data(forType: .tiff), datos.count < 30_000_000,
                  let rep = NSBitmapImageRep(data: datos), let png = rep.representation(using: .png, properties: [:]) {
            let nombre = UUID().uuidString + ".png"
            guard (try? png.write(to: Portapapeles.carpeta.appendingPathComponent(nombre))) != nil else { return }
            sumar(ElementoCopiado(tipo: .imagen, imagen: nombre, app: app))
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sumar(ElementoCopiado(tipo: .texto, texto: String(s.prefix(100_000)), app: app))
        }
    }

    func sumarTexto(_ s: String, app: String?) {
        sumar(ElementoCopiado(tipo: .texto, texto: s, app: app))
    }

    private func sumar(_ e: ElementoCopiado) {
        // Si ya estaba (mismo texto o mismos archivos), sube arriba en vez de repetirse.
        if let i = elementos.firstIndex(where: { $0.tipo == e.tipo && $0.tipo != .imagen && $0.texto == e.texto && $0.archivos == e.archivos }) {
            var viejo = elementos.remove(at: i)
            viejo.fecha = Date()
            elementos.insert(viejo, at: 0)
        } else {
            elementos.insert(e, at: 0)
        }
        podar()
    }

    func borrar(_ e: ElementoCopiado) {
        elementos.removeAll { $0.id == e.id }
        guardar(); borrarImagenesSueltas()
    }

    func vaciar() { elementos = []; guardar(); borrarImagenesSueltas() }

    func podar() {
        let limite = Date().addingTimeInterval(-Portapapeles.horas * 3600)
        elementos = Array(elementos.filter { $0.fecha > limite }.prefix(Portapapeles.maximo))
        guardar(); borrarImagenesSueltas()
    }

    private func guardar() { Almacen.guardar(elementos, "portapapeles.json") }

    private func borrarImagenesSueltas() {
        Almacen.borrarSueltos(en: Portapapeles.carpeta, extension: "png", vivos: Set(elementos.compactMap(\.imagen)))
    }

    // Miniatura de 96 px para la lista (no se carga la imagen entera); se guardan como mucho 60 en memoria.
    private let miniaturas: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 60; return c }()

    func miniatura(_ e: ElementoCopiado) -> NSImage? {
        let clave = e.id.uuidString as NSString
        if let m = miniaturas.object(forKey: clave) { return m }
        var url: URL?
        if let n = e.imagen { url = Almacen.archivoPropio(n, extension: "png", en: Portapapeles.carpeta) }
        else if e.tipo == .archivos, let p = e.archivos?.first {
            let ext = (p as NSString).pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"].contains(ext) { url = URL(fileURLWithPath: p) }
            else { let icono = NSWorkspace.shared.icon(forFile: p); miniaturas.setObject(icono, forKey: clave); return icono }
        }
        guard let u = url, let fuente = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opciones = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96,
                        kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        miniaturas.setObject(img, forKey: clave)
        return img
    }

    private func imagenCompleta(_ e: ElementoCopiado) -> NSImage? {
        guard let n = e.imagen, let u = Almacen.archivoPropio(n, extension: "png", en: Portapapeles.carpeta) else { return nil }
        return NSImage(contentsOf: u)
    }

    // Pone el elemento en el portapapeles (sin que vuelva a anotarse) y lo pega donde estabas.
    func pegar(_ e: ElementoCopiado) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch e.tipo {
        case .texto: pb.setString(e.texto ?? "", forType: .string)
        case .imagen: if let img = imagenCompleta(e) { pb.writeObjects([img]) }
        case .archivos: pb.writeObjects((e.archivos ?? []).map { URL(fileURLWithPath: $0) as NSURL })
        }
        Cursor.cambiosPropios.insert(pb.changeCount)
        sumar(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Cursor.pegarPortapapeles() }
    }
}

// Ventana flotante (tipo Spotlight) que recibe el teclado sin sacarle el foco a la app donde estabas.
final class PanelFlotante: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class VentanaPortapapeles: NSObject, NSWindowDelegate {
    private var panel: PanelFlotante?
    private var monitor: Any?
    private let estado = EstadoPortapapeles()

    var visible: Bool { panel?.isVisible == true }

    func alternar() { visible ? cerrar() : abrir() }

    func abrir() {
        if panel == nil {
            let p = PanelFlotante(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
                                  styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                  backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.delegate = self
            p.contentView = NSHostingView(rootView: VistaPortapapeles(portapapeles: .shared, estado: estado,
                                                                      elegir: { [weak self] e in self?.elegir(e) }))
            panel = p
        }
        estado.busqueda = ""
        estado.seleccion = 0
        let mouse = NSEvent.mouseLocation
        let pantalla = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let a = pantalla?.visibleFrame, let p = panel {
            p.setFrameOrigin(NSPoint(x: a.midX - p.frame.width / 2, y: a.midY - p.frame.height / 2 + a.height * 0.08))
        }
        panel?.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in self?.tecla(ev) ?? ev }
    }

    // Al cerrarse se libera entera (vistas y miniaturas en pantalla); se vuelve a armar al abrirla.
    func cerrar() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        guard let p = panel else { return }
        panel = nil
        p.delegate = nil
        p.orderOut(nil)
        p.contentView = nil
    }

    func windowDidResignKey(_ n: Notification) { cerrar() }

    private func elegir(_ e: ElementoCopiado) {
        cerrar()
        Portapapeles.shared.pegar(e)
    }

    private func tecla(_ ev: NSEvent) -> NSEvent? {
        let lista = estado.filtrados(Portapapeles.shared.elementos)
        switch ev.keyCode {
        case 53: cerrar(); return nil                                             // Esc
        case 125: estado.seleccion = min(estado.seleccion + 1, max(0, lista.count - 1)); return nil
        case 126: estado.seleccion = max(estado.seleccion - 1, 0); return nil
        case 36, 76:                                                              // Return
            if lista.indices.contains(estado.seleccion) { elegir(lista[estado.seleccion]) }
            return nil
        case 51 where ev.modifierFlags.contains(.command):                       // ⌘⌫ borra
            if lista.indices.contains(estado.seleccion) { Portapapeles.shared.borrar(lista[estado.seleccion]) }
            return nil
        default:
            if ev.modifierFlags.contains(.command), let c = ev.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n) {
                if lista.indices.contains(n - 1) { elegir(lista[n - 1]) }
                return nil
            }
            return ev
        }
    }
}

final class EstadoPortapapeles: ObservableObject {
    @Published var busqueda = "" { didSet { seleccion = 0 } }
    @Published var seleccion = 0

    func filtrados(_ todos: [ElementoCopiado]) -> [ElementoCopiado] {
        let b = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        guard !b.isEmpty else { return todos }
        return todos.filter { $0.resumen.lowercased().contains(b) || ($0.app ?? "").lowercased().contains(b) }
    }
}

struct VistaPortapapeles: View {
    @ObservedObject var portapapeles: Portapapeles
    @ObservedObject var estado: EstadoPortapapeles
    let elegir: (ElementoCopiado) -> Void

    var body: some View {
        let lista = estado.filtrados(portapapeles.elementos)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(Tema.apagado)
                TextField(T("Buscar en lo que copiaste hoy", "Search what you copied today"), text: $estado.busqueda)
                    .textFieldStyle(.plain).font(.system(size: 15))
                Text(verbatim: "24 h").font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.apagado)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Tema.relleno))
            }
            .padding(.horizontal, 16).frame(height: 48)
            Rectangle().fill(Tema.bordeSuave).frame(height: 1)
            if lista.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Tema.apagado)
                    Text(portapapeles.elementos.isEmpty ? T("Todavía no copiaste nada hoy.", "Nothing copied today yet.") : T("Sin coincidencias.", "No matches."))
                        .font(.system(size: 13)).foregroundStyle(Tema.apagado)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { lector in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(lista.enumerated()), id: \.element.id) { i, e in
                                FilaCopiado(elemento: e, indice: i, seleccionado: i == estado.seleccion, imagen: portapapeles.miniatura(e))
                                    .id(e.id)
                                    .onTapGesture { elegir(e) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: estado.seleccion) { _, s in
                        if lista.indices.contains(s) { lector.scrollTo(lista[s].id, anchor: .center) }
                    }
                }
            }
            Rectangle().fill(Tema.bordeSuave).frame(height: 1)
            HStack(spacing: 14) {
                Atajito(teclas: "↩", texto: T("Pegar", "Paste"))
                Atajito(teclas: "⌘1–9", texto: T("Pegar rápido", "Quick paste"))
                Atajito(teclas: "⌘⌫", texto: T("Borrar", "Delete"))
                Spacer()
                Atajito(teclas: "Esc", texto: T("Cerrar", "Close"))
            }
            .padding(.horizontal, 14).frame(height: 34)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.tarjeta))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tema.borde, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Tema.texto)
    }
}

private struct FilaCopiado: View {
    let elemento: ElementoCopiado
    let indice: Int
    let seleccionado: Bool
    let imagen: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = imagen {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "text.alignleft").font(.system(size: 15)).foregroundStyle(Tema.apagado)
                }
            }
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(Tema.rellenoSuave))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(elemento.resumen.replacingOccurrences(of: "\n", with: " ⏎ "))
                    .font(.system(size: 13)).lineLimit(2).foregroundStyle(Tema.titulo)
                HStack(spacing: 6) {
                    if let a = elemento.app { Text(a) }
                    Text(elemento.fecha.formatted(.relative(presentation: .named).locale(IdiomaInterfaz.locale)))
                }
                .font(.system(size: 11)).foregroundStyle(Tema.apagado)
            }
            Spacer(minLength: 0)
            if indice < 9 {
                Text("⌘\(indice + 1)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Tema.apagado)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(seleccionado ? Tema.relleno : .clear))
        .contentShape(Rectangle())
    }
}

private struct Atajito: View {
    let teclas: String
    let texto: String
    var body: some View {
        HStack(spacing: 5) {
            Text(teclas).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Tema.relleno))
            Text(texto).font(.system(size: 11))
        }
        .foregroundStyle(Tema.apagado)
    }
}
