# FluidAudio (copia recortada)

- Origen: https://github.com/FluidInference/FluidAudio, etiqueta **v0.17.7** (commit 503b4bd, 7/10/2026). Licencia Apache 2.0 (`LICENSE`).
- Se dejó solo voz a texto (Parakeet) y lo que necesita. Se sacaron: CLI, pruebas, voz sintética (TTS), separador de
  voces (Diarizer), realce de audio, Canary, Cohere, Paraformer, SenseVoice, `Decision`, `FastClusterWrapper` (C++, solo lo usaba el separador) y el normalizador binario
  `NemoTextProcessing` (opcional en FluidAudio: sin él el texto queda igual).
- Para que compile sin esas partes se conservaron solo estos archivos de tipos (los nombra el registro de modelos):
  `Diarizer/Core/DiarizerTypes.swift`, `Diarizer/Sortformer/SortformerTypes.swift`, `TTS/PocketTTS/PocketTtsConstants.swift`,
  `TTS/Inflect/InflectConstants.swift`, `TTS/Inflect/InflectVariant.swift`, `TTS/Chatterbox/Nano/ChatterboxNanoConstants.swift`,
  `ASR/Canary/CanaryConfig.swift`, `Enhancement/LocalVQE/LocalVqeTypes.swift`.
- Único cambio de código: en `LocalVqeTypes.swift`, `LocalVqeManager.hopSize` se reemplazó por su valor (256).
