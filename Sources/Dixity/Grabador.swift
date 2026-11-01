import AVFoundation
import CoreAudio

// Graba el micrófono en 16 kHz, mono, 16 bits (lo que piden las API de voz) y mide el volumen.
// El motor de audio se crea al empezar y se libera al terminar: entre dictados no queda nada abierto.
final class Grabador {
    private var motor: AVAudioEngine?
    private var conversor: AVAudioConverter?
    private let formatoSalida = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var muestras = Data()
    private let cola = DispatchQueue(label: "dixity.grabador")
    private(set) var grabando = false
    private(set) var dispositivo: AudioDeviceID = 0   // con qué micrófono está grabando (para --probar-microfono)
    var alNivel: ((Float) -> Void)?
    static let maximoSegundos: Double = 600

    static func pedirPermiso(_ listo: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: listo(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { listo(ok) } }
        default: listo(false)
        }
    }

    static var permitido: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    // `microfono`: el identificador elegido en Voz › Reconocimiento. Si no está conectado, graba con el de la Mac.
    func empezar(microfono: String = "") throws {
        guard !grabando else { return }
        cola.sync { muestras = Data(); muestras.reserveCapacity(32_000 * 20) }
        let motor = AVAudioEngine()
        let entrada = motor.inputNode
        if var id = Microfonos.dispositivo(microfono), let unidad = entrada.audioUnit {
            AudioUnitSetProperty(unidad, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else { throw ErrorApp.sinMicrofono }
        conversor = AVAudioConverter(from: formato, to: formatoSalida)
        entrada.installTap(onBus: 0, bufferSize: 2048, format: formato) { [weak self] buffer, _ in
            self?.recibir(buffer)
        }
        motor.prepare()
        do { try motor.start() } catch { entrada.removeTap(onBus: 0); conversor = nil; throw error }
        self.motor = motor
        grabando = true
        if let unidad = entrada.audioUnit {
            var tam = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioUnitGetProperty(unidad, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dispositivo, &tam)
        }
    }

    private func recibir(_ buffer: AVAudioPCMBuffer) {
        guard let conv = conversor else { return }
        let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 64
        guard let salida = AVAudioPCMBuffer(pcmFormat: formatoSalida, frameCapacity: capacidad) else { return }
        var entregado = false
        var error: NSError?
        conv.convert(to: salida, error: &error) { _, estado in
            if entregado { estado.pointee = .noDataNow; return nil }
            entregado = true
            estado.pointee = .haveData
            return buffer
        }
        guard error == nil, let ptr = salida.int16ChannelData?[0], salida.frameLength > 0 else { return }
        let n = Int(salida.frameLength)
        var suma: Float = 0
        for i in 0..<n { let v = Float(ptr[i]) / 32768; suma += v * v }
        let rms = sqrt(suma / Float(n))
        let nivel = min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 40))
        let trozo = Data(bytes: ptr, count: n * 2)
        cola.async { [weak self] in
            guard let self else { return }
            if Double(self.muestras.count) / 32_000 < Grabador.maximoSegundos {
                self.muestras.append(trozo)
            }
        }
        DispatchQueue.main.async { self.alNivel?(nivel) }
    }

    // Devuelve el WAV y la duración en segundos.
    func terminar() -> (wav: Data, segundos: Double) {
        guard grabando else { return (Data(), 0) }
        motor?.inputNode.removeTap(onBus: 0)
        motor?.stop()
        motor = nil
        conversor = nil
        grabando = false
        let pcm = cola.sync { () -> Data in let m = muestras; muestras = Data(); return m }
        return (Grabador.wav(pcm), Double(pcm.count) / 32_000)
    }

    func cancelar() { _ = terminar() }

    private static func wav(_ pcm: Data) -> Data {
        var d = Data()
        d.reserveCapacity(44 + pcm.count)
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count))
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}

// Los micrófonos conectados (Core Audio). Se guardan por su identificador, que no cambia al desconectarlos.
struct Microfono: Identifiable, Hashable {
    let id: String        // vacío = el de la Mac (el que elegiste en Ajustes del Sistema › Sonido)
    let nombre: String
}

enum Microfonos {
    static var sistema: Microfono { Microfono(id: "", nombre: T("El de la Mac", "System default")) }

    static func lista() -> [Microfono] {
        dispositivos().compactMap { d in
            guard let uid = texto(d, kAudioDevicePropertyDeviceUID), let nombre = texto(d, kAudioObjectPropertyName) else { return nil }
            return Microfono(id: uid, nombre: nombre)
        }
    }

    static func nombre(_ id: AudioDeviceID) -> String { texto(id, kAudioObjectPropertyName) ?? "?" }

    // El dispositivo de ese identificador, si está conectado.
    static func dispositivo(_ uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        return dispositivos().first { texto($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    // Solo los que tienen entrada de audio.
    private static func dispositivos() -> [AudioDeviceID] {
        var dir = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(tam) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids.filter { id in
            var entradas = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
                                                      mElement: kAudioObjectPropertyElementMain)
            var t: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &entradas, 0, nil, &t) == noErr && t > 0
        }
    }

    private static func texto(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var dir = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var valor: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &dir, 0, nil, &tam, &valor) == noErr, let v = valor else { return nil }
        return v.takeRetainedValue() as String
    }
}
