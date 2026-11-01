import AppKit
import Combine
import SwiftUI

enum Pagina: String, CaseIterable, Identifiable {
    case atajos, varita, modos, voz, diccionario, historial, proveedores, general
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .atajos: T("Atajos", "Shortcuts")
        case .varita: T("Varita", "Wonder")
        case .modos: T("Modos", "Modes")
        case .voz: T("Voz", "Voice")
        case .diccionario: T("Diccionario", "Dictionary")
        case .historial: T("Historial", "History")
        case .proveedores: T("Proveedores", "Providers")
        case .general: T("General", "General")
        }
    }
    var icono: String {
        switch self {
        case .atajos: "command"
        case .varita: "cursorarrow.rays"
        case .modos: "wand.and.stars"
        case .voz: "mic"
        case .diccionario: "book.closed"
        case .historial: "clock.arrow.circlepath"
        case .proveedores: "key"
        case .general: "gearshape"
        }
    }
}

final class Navegacion: ObservableObject {
    @Published var pagina: Pagina = .atajos
    @Published var bienvenida = false
}

struct VistaPanel: View {
    let motor: Motor
    @ObservedObject var ajustes: Ajustes
    @ObservedObject var navegacion: Navegacion
    let pedirTeclado: () -> Void
    @Estado private var refresco = 0
    @Estado private var sobre: Pagina?
    private let reloj = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            barraLateral
                .padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pagina
                }
                .frame(maxWidth: Tema.anchoPagina, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(navegacion.pagina)
            .transition(.opacity)
        }
        .background(Tema.fondo)
        .foregroundStyle(Tema.texto)
        .focusEffectDisabled()
        .onReceive(reloj) { _ in refresco += 1 }
        .sheet(isPresented: $navegacion.bienvenida) {
            Bienvenida(ajustes: ajustes, motor: motor, pedirTeclado: pedirTeclado, cerrar: { navegacion.bienvenida = false })
        }
    }

    @ViewBuilder private var pagina: some View {
        switch navegacion.pagina {
        case .atajos: PaginaAtajos(ajustes: ajustes, motor: motor)
        case .varita: PaginaVarita(ajustes: ajustes, motor: motor, refresco: refresco)
        case .modos: PaginaModos(ajustes: ajustes, motor: motor)
        case .voz: PaginaVoz(ajustes: ajustes)
        case .diccionario: PaginaDiccionario(diccionario: .shared)
        case .historial: PaginaHistorial(historial: .shared, motor: motor)
        case .proveedores: PaginaProveedores(ajustes: ajustes)
        case .general: PaginaGeneral(ajustes: ajustes, motor: motor, refresco: refresco, pedirTeclado: pedirTeclado,
                                     verBienvenida: { navegacion.bienvenida = true })
        }
    }

    private func atencion(_ p: Pagina) -> Bool {
        _ = refresco
        switch p {
        case .proveedores: return ajustes.faltanClaves
        case .general: return !Cursor.accesibilidadPermitida || !Grabador.permitido
        case .diccionario: return !Sugerencias.shared.lista.isEmpty
        default: return false
        }
    }

    private var barraLateral: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                LogoApp(tam: 38)
                Text(verbatim: "Dixity").font(.titulo(18, .semibold)).foregroundStyle(Tema.titulo)
            }
            .padding(12)
            .frame(height: 52)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Pagina.allCases) { p in
                    Button { withAnimation(.easeOut(duration: 0.15)) { navegacion.pagina = p } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: p.icono)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Tema.rellenoSuave))
                                .foregroundStyle(Tema.titulo)
                            Text(p.titulo).font(.titulo(14))
                                .foregroundStyle(navegacion.pagina == p ? Tema.titulo : Tema.subtitulo)
                            Spacer()
                            if atencion(p) {
                                Circle().fill(p == .diccionario ? Tema.acento : Tema.error).frame(width: 6, height: 6).padding(.trailing, 10)
                            }
                        }
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(navegacion.pagina == p ? Tema.relleno : (sobre == p ? Tema.rellenoSuave : .clear)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)            // sin el recuadro azul de foco que quedaba pegado
                    .onHover { dentro in sobre = dentro ? p : (sobre == p ? nil : sobre) }
                }
            }
            Spacer()
            PieHalyon()
        }
        .padding(.top, 28)
        .padding([.horizontal, .bottom], 12)
        .frame(width: Tema.anchoBarra)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tema.tarjeta.opacity(0.8)))
        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
    }
}

// Atribución del desarrollo (regla de Halyon Team).
struct PieHalyon: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(T("Desarrollado por", "Developed by"))
                Link(destination: URL(string: "https://halyon.team")!) {
                    Text(verbatim: "Halyon Team").fontWeight(.semibold).underline(pattern: .dot)
                }
                .foregroundStyle(Tema.subtitulo)
            }
            Text(T("Hecho en Argentina 🇦🇷", "Made in Argentina 🇦🇷"))
        }
        .font(.system(size: 11))
        .foregroundStyle(Tema.apagado)
        .padding(8)
    }
}

// El logo de la app (el mismo ícono del Dock). El ícono trae un margen transparente: se agranda un poco para llenar.
struct LogoApp: View {
    var tam: CGFloat
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(1.22)
            .frame(width: tam, height: tam)
    }
}

// MARK: Piezas comunes

struct TituloPagina: View {
    let titulo: String
    var subtitulo: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo).font(.titulo(20)).foregroundStyle(Tema.titulo)
            if let s = subtitulo { Text(s).font(.system(size: 14)).foregroundStyle(Tema.apagado) }
        }
    }
}

struct Tarjeta<C: View>: View {
    var titulo: String? = nil
    @ViewBuilder var contenido: C
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = titulo {
                Text(t).font(.titulo(13)).foregroundStyle(Tema.apagado).padding(.leading, 4)
            }
            VStack(spacing: 0) { contenido }
                .background(RoundedRectangle(cornerRadius: Tema.radioTarjeta).fill(Tema.tarjeta))
                .shadow(color: .black.opacity(0.02), radius: 4, y: 2)
        }
    }
}

struct Fila<D: View>: View {
    let titulo: String
    var detalle: String? = nil
    var divisor = true
    @ViewBuilder var derecha: D
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titulo).font(.titulo(14, .regular)).foregroundStyle(Tema.titulo)
                    if let d = detalle {
                        Text(d).font(.system(size: 12)).foregroundStyle(Tema.apagado).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) { derecha }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 44)
            if divisor { Rectangle().fill(Tema.bordeSuave).frame(height: 1).padding(.leading, 16) }
        }
    }
}

struct BotonSecundario: View {
    let texto: String
    var icono: String? = nil
    var peligro = false
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            HStack(spacing: 6) {
                if let i = icono { Image(systemName: i).font(.system(size: 12, weight: .medium)) }
                Text(texto).font(.titulo(13)).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(Tema.relleno))
            .foregroundStyle(peligro ? Tema.error : Tema.titulo)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct BotonPrimario: View {
    let texto: String
    let accion: () -> Void
    var body: some View {
        Button(action: accion) {
            Text(texto).font(.titulo(13))
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(Tema.pildora))
                .foregroundStyle(Tema.pildoraTexto)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Tecla dibujada como tecla física.
struct TeclaVisual: View {
    let texto: String
    var grande = false
    var resaltada = false
    var body: some View {
        Text(texto)
            .font(.system(size: grande ? 20 : 12, weight: .medium))
            .lineLimit(1).minimumScaleFactor(0.7)   // "⌃ right" no se parte en dos renglones
            .padding(.horizontal, grande ? 10 : 6)
            .frame(minWidth: grande ? 36 : 22, minHeight: grande ? 40 : 22)
            .background(RoundedRectangle(cornerRadius: grande ? 8 : 5).fill(Tema.tarjeta))
            .overlay(RoundedRectangle(cornerRadius: grande ? 8 : 5)
                .strokeBorder(resaltada ? Tema.acento : Tema.borde, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 0, y: 1.5)
            .foregroundStyle(resaltada ? Tema.acento : Tema.subtitulo)
    }
}

struct Teclas: View {
    let atajo: Atajo
    var grande = false
    var body: some View {
        HStack(spacing: grande ? 6 : 3) {
            ForEach(Array(atajo.partes.enumerated()), id: \.offset) { _, p in TeclaVisual(texto: p, grande: grande) }
        }
    }
}

// Selector propio: menú con el valor actual y una tilde en el elegido.
struct Selector<V: Hashable & Identifiable>: View {
    @Binding var valor: V
    let opciones: [V]
    let nombre: (V) -> String
    var ancho: CGFloat = 200
    @Estado private var sobre = false

    var body: some View {
        Menu {
            ForEach(opciones) { o in
                Button { valor = o } label: {
                    if o == valor { Label(nombre(o), systemImage: "checkmark") } else { Text(nombre(o)) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(nombre(valor)).font(.system(size: 13)).lineLimit(1).foregroundStyle(Tema.titulo)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Tema.apagado)
            }
            .padding(.horizontal, 10)
            .frame(width: ancho, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sobre ? Tema.relleno : Tema.rellenoSuave))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Tema.bordeSuave))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { sobre = $0 }
    }
}

// Botones segmentados propios (para opciones cortas como el tamaño).
struct Segmentos<V: Hashable & Identifiable>: View {
    @Binding var valor: V
    let opciones: [V]
    let nombre: (V) -> String
    @Namespace private var espacio

    var body: some View {
        HStack(spacing: 2) {
            ForEach(opciones) { o in
                Button { withAnimation(Tema.expo) { valor = o } } label: {
                    Text(nombre(o)).font(.system(size: 12, weight: o == valor ? .semibold : .regular))
                        .foregroundStyle(o == valor ? Tema.titulo : Tema.apagado)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background {
                            if o == valor {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Tema.tarjeta)
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "elegido", in: espacio)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tema.relleno))
    }
}
