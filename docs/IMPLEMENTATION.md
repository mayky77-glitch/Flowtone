# Flowtone Implementation Guide

## Current vertical slice

Текущий milestone проверяет границы между приложением и inference runtime. Он не выдаёт synthetic engine за музыкальную модель.

```text
SwiftUI App
    └── FlowtoneCore
        ├── StationConfiguration + PromptComposer
        ├── ModelRecommender + ResourcePolicy
        ├── GenerationScheduler (actor, one job)
        ├── TrackTitleGenerator (local deterministic names)
        ├── TrackLibrary (JSON index + local audio files)
        ├── RadioPlaybackQueue (current + 2 ready)
        ├── AudioPlaybackController (two AVAudioPlayerNode instances)
        ├── EqualPowerCrossfade
        ├── ModelRuntimeCatalog
        └── GenerationEngine
            ├── SyntheticAudioEngine (development only)
            └── StableAudioMLXEngine (official CLI process adapter)
```

## Build and test

```bash
swift build
swift test
```

Тесты используют официальный пакет [swift-testing](https://github.com/swiftlang/swift-testing), закреплённый на revision для Swift 6.3.3. На машине только с Command Line Tools linker получает системный `_TestingInterop` из стандартного CLT path.

## Development audio smoke test

```bash
swift run flowtone-spike \
  --engine synthetic \
  --duration 5 \
  --seed 42 \
  --genres ambient,lo-fi \
  --tempo 82 \
  --vibe "rain outside"
```

Synthetic engine создаёт простой stereo WAV 44.1 kHz. Его задача — проверить scheduler, file contract и playback без большой загрузки.

## Local radio library

Коллекция хранится в `~/Library/Application Support/Flowtone/Library`:

```text
Library/
├── library-v1.json
├── Audio/
└── Incoming/
```

JSON index хранит название, жанры, лайк, размер, длительность, model engine, seed и playback history. При превышении лимита сначала удаляются самые давно не воспроизводившиеся треки без лайка. Лайкнутый и текущий трек защищены.

Текущий и оба подготовленных трека защищены от ручной и автоматической очистки. Player заранее
планирует следующий файл, а `AudioPlaybackController` определяет момент перехода по render time.
SwiftUI-таймер только вызывает наблюдение за render clock; он не рассчитывает позицию аудио.

Названия создаются локально и детерминированно из genre + energy + mood + vibe + seed. Это не требует отдельного запуска LLM. Старые index records без `title` получают стабильное fallback-название при декодировании.

## Stable Audio 3 Small MLX

Flowtone следует официальному [`optimized/mlx`](https://github.com/Stability-AI/stable-audio-3/tree/main/optimized/mlx) runtime. Adapter запускает executable напрямую через `Process`; prompt не передаётся shell и не интерполируется.

Перед загрузкой:

1. Прочитайте [Stable Audio Community License](https://stability.ai/license).
2. Убедитесь, что условия подходят вашему использованию.
3. Примите необходимые gated model terms на Hugging Face.

Установка runtime выполняется вне Flowtone repository, чтобы веса и Python environment не попали в Git:

```bash
mkdir -p Models
git clone https://github.com/Stability-AI/stable-audio-3.git Models/stable-audio-3
cd Models/stable-audio-3/optimized/mlx
./install.sh
cd -
```

После установки:

```bash
swift run flowtone-spike \
  --engine stable-audio \
  --sa3-executable "./Models/stable-audio-3/optimized/mlx/sa3" \
  --duration 30 \
  --genres ambient,lo-fi \
  --tempo 82 \
  --vibe "rain outside"
```

Чтобы SwiftUI-приложение обнаружило runtime, создайте исполняемый файл или симлинк по фиксированному
локальному пути (веса в репозиторий не копируются):

```bash
mkdir -p "$HOME/Library/Application Support/Flowtone"
ln -s "/absolute/path/to/stable-audio-3/optimized/mlx/sa3" \
  "$HOME/Library/Application Support/Flowtone/stable-audio-mlx"
```

Release-приложение не включает synthetic fallback. Если executable отсутствует или не имеет права
на запуск, интерфейс честно показывает, что Stable Audio 3 не установлена, и продолжает играть
готовую локальную коллекцию. Quality tier пока показывает явный статус отсутствующего ACE-Step adapter.

Официальный CLI contract, который формирует adapter:

```text
sa3 --prompt <prompt> --negative-prompt <negative> \
    --dit sm-music --decoder same-s --seconds <1...120> \
    --steps 8 --seed <seed> --out <absolute WAV path>
```

## Current limitations

- Полный Xcode не установлен; SwiftPM build/test работает через Command Line Tools.
- Настоящие model weights ещё не загружены и benchmark не запускался.
- Нет model downloader, license acceptance UI и checksum verification.
- ACE-Step quality adapter ещё не реализован.
- Скрипт создаёт рабочий, но неподписанный `.app`; notarized `.dmg` требует Apple Developer credentials.
- Системная memory-pressure защита подключена через `DispatchSource`; её пороги остаются системными.

## Next implementation slice

1. Воспроизводимый Stable Audio benchmark: 5/30/120 секунд, wall time, peak RSS, thermal state.
2. Model downloader, installation state, checksum и явный license gate.
3. Системный memory-pressure monitor и длительный 10-часовой soak test.
4. Подписанный/notarized `.dmg` после выбора source license и получения credentials.

## Unsigned app bundle

```bash
scripts/package-app.sh /tmp/flowtone-package
open /tmp/flowtone-package/Flowtone.app
```

Скрипт отказывается перезаписывать существующий bundle, включает `Assets/AppIcon.icns` и не выполняет signing или notarization.
