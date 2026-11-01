import AppKit
import SwiftUI

// Lo que se ve de la Varita (además de la flecha): el borde que marca lo que está debajo del puntero, las marcas de lo
// elegido y la cajita de sugerencias que va abajo a la derecha del cursor. Son ventanitas chicas que no se pueden
// tocar (salvo la cajita cuando hay algo elegido) y se crean al prender la Varita y se destruyen al apagarla.

// Un resorte: llega sin pasarse y anda igual a cualquier velocidad de pantalla (pasitos de 1/240 s).
struct Resorte {
    var valor: CGFloat
    var velocidad: CGFloat = 0
    mutating func mover(a meta: CGFloat, dt: CGFloat, rigidez: CGFloat, amortiguado: CGFloat = 0.9) {
        let freno = 2 * rigidez.squareRoot() * amortiguado
        let pasos = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / CGFloat(pasos)
        for _ in 0..<pasos {
            velocidad += ((meta - valor) * rigidez - velocidad * freno) * h
            valor += velocidad * h
        }
    }
}

struct ResorteRect {
    var x, y, ancho, alto: Resorte
    init(_ r: CGRect) { x = Resorte(valor: r.minX); y = Resorte(valor: r.minY); ancho = Resorte(valor: r.width); alto = Resorte(valor: r.height) }
    var rect: CGRect { CGRect(x: x.valor, y: y.valor, width: ancho.valor, height: alto.valor) }
    mutating func mover(a r: CGRect, dt: CGFloat, rigidez: CGFloat, amortiguado: CGFloat = 0.82) {
        x.mover(a: r.minX, dt: dt, rigidez: rigidez, amortiguado: amortiguado)
        y.mover(a: r.minY, dt: dt, rigidez: rigidez, amortiguado: amortiguado)
        ancho.mover(a: r.width, dt: dt, rigidez: rigidez, amortiguado: amortiguado)
        alto.mover(a: r.height, dt: dt, rigidez: rigidez, amortiguado: amortiguado)
    }
}

// Una ventanita transparente, por encima de todo y en todos los escritorios.
final class VentanaFlotante: NSPanel {
    init<V: View>(_ vista: V, tocable: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = !tocable
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        contentView = VistaClicable(rootView: vista)
    }
    override var canBecomeKey: Bool { false }
}

// MARK: - Borde de lo que está debajo

final class ModeloBorde: ObservableObject {
    @Published var etiqueta = ""
    @Published var visible = false
    @Published var elegido = false     // las marcas de lo elegido: borde lleno, sin etiqueta
    @Published var pensando = false
    @Published var nitido = false      // el recuadro del modo captura: filo limpio, sin el brillo que se veía como rebaba
}

struct VistaBorde: View {
    @ObservedObject var modelo: ModeloBorde
    static let margen: CGFloat = 14     // lugar para el brillo alrededor del borde
    // Los colores de la flecha de la Varita (celeste, azul y lavanda), así el borde se ve parte de ella y no un aviso.
    static let celeste = Color(hex: 0x9EEBFF), azul = Color(hex: 0x4D8CF7), lavanda = Color(hex: 0xB3ADFF)

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: modelo.nitido ? 3 : 12, style: .continuous)   // el recorte, casi recto
        let degradado = LinearGradient(colors: [Self.celeste, Self.azul, Self.lavanda], startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack(alignment: .topLeading) {
            forma
                .strokeBorder(degradado, lineWidth: modelo.nitido ? 1.5 : modelo.elegido ? 2.5 : 2)
                .background(forma.fill(Self.azul.opacity(modelo.nitido ? 0.06 : modelo.elegido ? 0.08 : 0)))
                .shadow(color: Self.azul.opacity(modelo.nitido ? 0 : 0.5), radius: 10)
                .shadow(color: Self.lavanda.opacity(modelo.nitido ? 0 : 0.3), radius: 18)
                .overlay {
                    if modelo.pensando { BordeGirando(forma: forma, color: Self.celeste) }
                }
            if !modelo.etiqueta.isEmpty && !modelo.elegido {
                Text(modelo.etiqueta).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).frame(height: 19)
                    .background(Capsule().fill(LinearGradient(colors: [Self.azul, Color(hex: 0x8B7CF6)], startPoint: .leading, endPoint: .trailing)))
                    .offset(x: 8, y: -10)
            }
        }
        .padding(VistaBorde.margen)
        .opacity(modelo.visible ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: modelo.visible)
    }
}

// MARK: - La cajita de sugerencias

struct SugerenciaVarita: Identifiable, Equatable {
    let id: String
    let nombre: String
    let icono: String
    let color: Color
}

final class ModeloCajita: ObservableObject {
    @Published var titulo = ""
    @Published var icono = "wand.and.stars"
    @Published var sugerencias: [SugerenciaVarita] = []
    @Published var miniaturas: [NSImage] = []
    @Published var marcada = 0
    @Published var elegida = false        // hay algo elegido con clic: la cajita se puede tocar
    @Published var visible = false
    @Published var pie = ""
    var alElegir: (SugerenciaVarita) -> Void = { _ in }
}

struct VistaCajita: View {
    @ObservedObject var modelo: ModeloCajita
    @Namespace private var espacio
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 17, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: modelo.icono).font(.system(size: 10.5, weight: .bold)).foregroundStyle(VistaBorde.azul)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VistaBorde.azul.opacity(0.15)))
                Text(modelo.titulo).font(.system(size: 12, weight: .semibold)).lineLimit(1).opacity(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.top, 9).padding(.bottom, 7)
            if !modelo.miniaturas.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(modelo.miniaturas.enumerated()), id: \.offset) { _, img in
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 38, height: 30).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(VistaBorde.azul, lineWidth: 1.5))
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 7)
            }
            VStack(spacing: 2) {
                ForEach(Array(modelo.sugerencias.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 9) {
                        Image(systemName: s.icono).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(s.color))
                        Text(s.nombre).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(i + 1)").font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.45)
                            .frame(width: 17, height: 17)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    }
                    .padding(.horizontal, 7).frame(height: 36)
                    .background {
                        if modelo.marcada == i {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VistaBorde.azul.opacity(0.12))
                                .matchedGeometryEffect(id: "marca", in: espacio)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { modelo.alElegir(s) }
                    // Sin rebote: con el resorte la marca se pasaba y volvía al ir de una opción a otra, y la cajita
                    // parecía temblar (01/11/2026).
                    .onHover { if $0, modelo.marcada != i { withAnimation(.easeOut(duration: 0.12)) { modelo.marcada = i } } }
                }
            }
            .padding(.horizontal, 5)
            if !modelo.pie.isEmpty {
                Text(modelo.pie).font(.system(size: 10.5)).opacity(0.5).padding(.horizontal, 11).padding(.top, 5)
            }
            Spacer().frame(height: 8)
        }
        .frame(width: 236)
        // Fondo liso y casi opaco, con un filo finito y una sombra corta. El vidrio de macOS 26 dejaba un halo claro
        // alrededor y un filo serruchado a los costados sobre fondos blancos (se vio el 31/10), y la sombra grande
        // se veía como una aureola gris.
        .background(forma.fill(Tema.dinamico(0xFBFAF9, 0x1F1F1E, alfaClaro: 0.98, alfaOscuro: 0.97)))
        .clipShape(forma)
        .overlay(forma.strokeBorder(Tema.dinamico(0x000000, 0xFFFFFF, alfaClaro: 0.14, alfaOscuro: 0.14), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
        .padding(18)   // lugar para la sombra
        .scaleEffect(modelo.visible || sinMovimiento ? 1 : 0.7, anchor: .topLeading)
        .opacity(modelo.visible ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: modelo.visible)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: modelo.miniaturas.count)
        .fixedSize()
    }
}
