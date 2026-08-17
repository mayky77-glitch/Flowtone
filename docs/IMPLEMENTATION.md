# Flowtone Implementation Guide

## Current vertical slice

Текущий milestone проверяет границы между приложением и inference runtime. Он не выдаёт synthetic engine за музыкальную модель.

```text
SwiftUI App
    └── FlowtoneCore
        ├── StationConfiguration + PromptComposer
        ├── GenrePromptCatalog + TempoPlanner
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

JSON index хранит название, жанры, лайк, размер, длительность, model engine, seed и playback metadata. Перед генерацией Flowtone резервирует место под следующий 120-секундный WAV. Если запись не помещается, приложение показывает системное предупреждение, прекращает создавать новые файлы и продолжает играть коллекцию. Генерация возобновляется после ручной очистки или увеличения лимита; автоматического удаления ради новой записи нет.

Текущий и оба подготовленных трека защищены от ручного удаления и массовой очистки. Player заранее
планирует следующий файл, а `AudioPlaybackController` определяет момент перехода по render time.
SwiftUI-таймер только вызывает наблюдение за render clock; он не рассчитывает позицию аудио.

Названия создаются локально и детерминированно из genre + energy + mood + vibe-hash + seed. Сырой vibe не копируется в заголовок, поэтому он не обрывается на предлоге. Старые обрезанные titles и index records без `title` получают стабильное fallback-название при декодировании.

`TempoPlanner` выбирает BPM из жанровых диапазонов, смещает его по энергии и иногда даёт ограниченное отклонение. `GenrePromptCatalog` задаёт ритм, тембры, фактуру и русское название 292 пресетов для 27 жанров. Каждый жанр имеет минимум десять пресетов; Fantasy, Pirate, Light Rave, Cyberpunk и Funk имеют расширенные наборы. `GenreMixPlanner` детерминированно выбирает по seed от двух до пяти разных активных жанров, а `PromptComposer` сохраняет первый жанр ведущим по ритму и форме.

Player поддерживает seek, начало/конец, ±15 секунд, previous/next по session history и запуск выбранного трека из коллекции. Vinyl drag перемещает ту же audio position; forward/reverse preview использует чередующиеся player nodes, короткие PCM-буферы с envelope и varispeed. При pause автовращение останавливается; тонарм идёт к центру по реальному progress.

## Stable Audio 3 Small MLX

Flowtone следует официальному [`optimized/mlx`](https://github.com/Stability-AI/stable-audio-3/tree/main/optimized/mlx) runtime. Adapter запускает executable напрямую через `Process`; prompt не передаётся shell и не интерполируется.

Перед ручной установкой:

1. Откройте [Stable Audio 3 Small-Music на Hugging Face](https://huggingface.co/stabilityai/stable-audio-3-small-music), войдите в свой аккаунт и сами примите gated model/Gemma terms.
2. Прочитайте [Stable Audio Community License](https://stability.ai/license) и убедитесь, что условия подходят вашему использованию.
3. Откройте официальный [Stable Audio 3 repository](https://github.com/Stability-AI/stable-audio-3) и его [MLX instructions](https://github.com/Stability-AI/stable-audio-3/tree/main/optimized/mlx). Следуйте им вручную в отдельной от Flowtone директории.

В приложении есть локальная отметка о том, что пользователь лично открыл и прочитал официальные страницы. Она записывается только локально и не означает принятие Flowtone внешних Hugging Face, Stability или Gemma terms, не предоставляет доступ к gated model и не заменяет действия пользователя на соответствующих сервисах.

Не запускайте автоматическую установку из Flowtone: приложение и этот repository не скачивают веса, не принимают внешние terms и не выполняют `curl | bash`. Нет automatic downloader, checksum/provisioning или bundled weights. После ручной установки скопируйте или создайте symlink официального `./sa3` wrapper в фиксированном пути Flowtone:

```bash
mkdir -p "$HOME/Library/Application Support/Flowtone"
ln -s "/absolute/path/to/stable-audio-3/optimized/mlx/sa3" \
  "$HOME/Library/Application Support/Flowtone/stable-audio-mlx"
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

## Reproducible Stable Audio benchmark

После ручной установки запустите harness. Он не скачивает weights и не меняет runtime. Runtime запускается с `HF_HUB_OFFLINE=1` и `TRANSFORMERS_OFFLINE=1`, поэтому missing cached weights должны завершить run ошибкой, а не вызвать network provisioning. По умолчанию harness использует `~/Library/Application Support/Flowtone/stable-audio-mlx`, фиксированные prompt, negative prompt, 30 seconds, seed `424242`, MLX model flags `--dit sm-music --decoder same-s` и `--steps 8`.

```bash
scripts/benchmark-stable-audio.sh
```

По умолчанию WAV записывается в `${TMPDIR:-/tmp}/flowtone-stable-audio-benchmark.wav`; script не перезаписывает существующий файл. Для другой runtime или output path:

```bash
scripts/benchmark-stable-audio.sh \
  --executable "/absolute/path/to/stable-audio-3/optimized/mlx/sa3" \
  --output /tmp/flowtone-stable-audio-benchmark-run-1.wav
```

Успех печатается одной стабильной machine-readable строкой с `status=passed`, seed, requested seconds, wall time, размером и output path. Script проверяет executable до запуска и nonempty WAV после него. Сравнивайте runs на одинаковой версии runtime, macOS, питании и свободной памяти; benchmark пока не устанавливает production performance target.

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
- Веса не входят в Git/сборку. На тестовом M4/16 ГБ official Small-Music MLX runtime установлен вне репозитория; offline 30-second benchmark прошёл за 7.68 с process wall / 4.81 с model wall с stage peak 1.69 ГБ.
- Есть локальная UI-отметка о личном прочтении официальных страниц; она не принимает external terms и не даёт доступ к gated weights. Нет automatic downloader, checksum/provisioning или bundled weights.
- ACE-Step quality adapter ещё не реализован.
- Скрипт создаёт рабочий, но неподписанный `.app`. Signing/notarization намеренно вне scope repository Actions artifact и требуют отдельного решения владельца и credentials.
- Системная memory-pressure защита подключена через `DispatchSource`; её пороги остаются системными.

## Next implementation slice

1. Проверить лёгкий runtime на M1/M2 с 8–16 ГБ.
2. Проверить ACE-Step adapter для quality tier.
3. Signing/notarization остаются вне scope unsigned repository artifact; рассмотреть их только после отдельного решения владельца и получения credentials.

## Unsigned app bundle

```bash
scripts/package-app.sh /tmp/flowtone-package
open /tmp/flowtone-package/Flowtone.app
```

Скрипт отказывается перезаписывать существующий bundle, включает `Assets/AppIcon.icns` и не выполняет signing или notarization.

При `push` (включая tag) macOS CI упаковывает тот же bundle в `Flowtone-unsigned-macos.app.zip` c `ditto --keepParent` и сохраняет его как временный GitHub Actions artifact. Ни `.app`, ни ZIP в Git не коммитятся; GitHub Release не создаётся.
