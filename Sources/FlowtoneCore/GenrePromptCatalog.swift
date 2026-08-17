import Foundation

public struct GenrePreset: Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let productionPrompt: String

  public init(id: String, title: String, productionPrompt: String) {
    self.id = id
    self.title = title
    self.productionPrompt = productionPrompt
  }
}

/// Genre-specific production language for the local text-to-music model.
public struct GenrePromptCatalog: Sendable {
  public static let supportedGenres = [
    "Ambient", "Lo-fi", "Light Rave", "Fantasy", "Dark Empire", "Pirate", "Rock",
    "Metal", "Thrash Metal", "Cute", "Chaos", "Electronic", "Synthwave", "House",
    "Techno", "Hard Techno", "Industrial Techno", "Hardcore", "Psytrance", "Breakbeat",
    "Drum and Bass", "Cyberpunk", "Hip-hop", "Funk", "Jazz", "Classical", "Post-rock",
    "Cinematic",
  ]

  public init() {}

  public func presets(for genre: String) -> [GenrePreset] {
    Self.presetCatalog[genre] ?? Self.fallbackPresets
  }

  public func profile(
    for genre: String,
    seed: UInt64,
    energy: EnergyLevel = .balanced,
    presetID: String? = nil
  ) -> String {
    let candidates = presets(for: genre)
    if let presetID, let selected = candidates.first(where: { $0.id == presetID }) {
      return selected.productionPrompt
    }

    let archetypeCount = candidates.count / Self.arrangements.count
    let archetypeIndex = Int(Self.mix(seed) % UInt64(archetypeCount))
    let arrangementIndex: Int =
      switch energy {
      case .calm: 0
      case .balanced:
        Int(Self.mix(seed &+ 0xD1B5_4A32_D192_ED03) % UInt64(Self.arrangements.count))
      case .driving: Self.arrangements.count - 1
      }
    return candidates[archetypeIndex * Self.arrangements.count + arrangementIndex].productionPrompt
  }

  public func profileCount(for genre: String) -> Int {
    presets(for: genre).count
  }

  private struct Archetype: Sendable {
    let id: String
    let title: String
    let detail: String
  }

  private struct Definition: Sendable {
    let base: String
    let archetypes: [Archetype]
  }

  private struct Arrangement: Sendable {
    let id: String
    let title: String
    let detail: String
  }

  private static func a(_ id: String, _ title: String, _ detail: String) -> Archetype {
    Archetype(id: id, title: title, detail: detail)
  }

  private static func makePresets(for definition: Definition) -> [GenrePreset] {
    definition.archetypes.flatMap { archetype in
      arrangements.map { arrangement in
        GenrePreset(
          id: "\(archetype.id)-\(arrangement.id)",
          title: "\(archetype.title) · \(arrangement.title)",
          productionPrompt: "\(definition.base), \(archetype.detail), \(arrangement.detail)"
        )
      }
    }
  }

  private static let arrangements = [
    Arrangement(
      id: "steady",
      title: "ровный эфир",
      detail:
        "controlled radio arrangement, stable groove, patient development, restrained transitions"
    ),
    Arrangement(
      id: "charged",
      title: "живой разгон",
      detail:
        "active arrangement, stronger rhythmic motion, surprising but coherent contrast, decisive climax"
    ),
  ]

  private static let fallback = Definition(
    base: "instrumental ensemble, recognizable genre language, natural dynamics",
    archetypes: [
      a("organic", "Живой ансамбль", "acoustic colors and human timing"),
      a("electric", "Электрический контур", "electric timbres and a memorable hook"),
      a("minimal", "Чистый минимализм", "few elements with precise repetition"),
      a("cinematic", "Широкий кадр", "narrative arc and spacious production"),
      a("experimental", "Неожиданный поворот", "unusual texture anchored by a recurring motif"),
    ]
  )

  private static let definitions: [String: Definition] = [
    "Ambient": Definition(
      base: "ambient instrumental, spacious natural reverb, slow harmonic movement, no drums",
      archetypes: [
        a("warm-pads", "Тёплые облака", "evolving analog pads, low drone, sparse felt piano"),
        a("organic-air", "Дыхание леса", "breathy woodwinds, bowed textures, gentle overtones"),
        a("granular-night", "Зерно ночи", "granular air, distant chimes, dark subharmonic bed"),
        a("oceanic", "Глубокая вода", "slow tidal swells, glass harmonics, wide stereo space"),
        a(
          "cosmic", "Тихая орбита",
          "weightless synthesizer layers, subtle pulses, luminous upper partials"),
      ]
    ),
    "Lo-fi": Definition(
      base: "lo-fi instrumental, warm cassette texture, relaxed pocket, intimate room sound",
      archetypes: [
        a("study", "Поздняя учёба", "dusty boom-bap drums, mellow Rhodes chords, rounded bass"),
        a("rain", "Дождь на кассете", "muted piano loop, brushed drums, rain-like tape hiss"),
        a("jazz-guitar", "Старое кафе", "sampled jazz guitar, upright-like bass, soft swung snare"),
        a("window", "Окно во двор", "music-box fragment, lazy breakbeat, neighborhood ambience"),
        a("sunset", "Закатный бит", "electric piano, nylon guitar flecks, warm side-chained pads"),
      ]
    ),
    "Light Rave": Definition(
      base:
        "instrumental Berlin rave and hard-dance continuum, elastic club low end, bright detailed top end, continuous dance-floor motion, no crowd and no vocals",
      archetypes: [
        a(
          "berlin-room", "Берлинская комната",
          "112 to 124 BPM body-moving groove, raw room drums, rolling bass, concise trance stabs, long blend-friendly development"
        ),
        a(
          "hard-dance", "Упругий танцпол",
          "bouncy hard-dance bass, bright rave chords, playful syncopation, crisp rapid percussion"),
        a(
          "euphoric", "Эйфория на рассвете",
          "euphoric trance arpeggio, brief piano lift, airy breakdown, quick return to the kick"),
        a(
          "acid", "Мягкая кислота",
          "restrained acid sequence, crisp hats, warm filtered build, rounded kick without harsh clipping"
        ),
        a(
          "break-rave", "Ломаный строб",
          "short breakbeat accents inside a steady pulse, elastic bass, compact rave-synth hook"),
        a(
          "hard-groove", "Берлинский hard groove",
          "tribal rolling drums, syncopated toms, short metallic loop, dense sixteenth-note motion"),
        a(
          "euro", "Еврорейв",
          "bright supersaw chord, galloping bass, playful retro dance motif, controlled euphoric peak"
        ),
      ]
    ),
    "Fantasy": Definition(
      base:
        "instrumental historical fantasy score, modal melody, realistic acoustic orchestration, ancient world atmosphere",
      archetypes: [
        a(
          "kingdom", "Древнее королевство",
          "noble horns, sweeping strings, frame drums, lute and hammered dulcimer"),
        a(
          "magic", "Зачарованный лес",
          "celesta, harp harmonics, glockenspiel, breathy flutes, mysterious magic"),
        a(
          "heroic", "Поход героев",
          "bold brass calls, urgent string ostinato, war drums, triumphant finale"),
        a(
          "skyrim-wilderness", "Skyrim · северная даль",
          "slow Nordic modal motif, open fifths, low strings, solo horn and wooden flute, very wide dynamics, mountain stillness"
        ),
        a(
          "skyrim-hall", "Skyrim · древний зал",
          "low bowed strings and brass shaped like a distant ceremonial chorus without voices, stone reverb, patient modal harmony"
        ),
        a(
          "skyrim-battle", "Skyrim · пробуждение дракона",
          "broad low horns, forceful orchestral unison, large frame drums, urgent strings, heroic ascent from sparse wilderness"
        ),
        a(
          "cave", "Пещеры и руны",
          "bone-flute timbre, primitive plucked strings, stone echoes, elemental mystery"),
        a(
          "dark-quest", "Проклятый поход",
          "bass clarinet, low strings, distant brass, tense ritual pulse"),
        a(
          "tavern", "Таверна у тракта",
          "lute, fiddle, hand drum, wooden flute, lively medieval dance"),
      ]
    ),
    "Dark Empire": Definition(
      base:
        "instrumental dark imperial fantasy, vivid full-spectrum theatrical production, punchy drums, crisp upper strings and brass, chromatic minor harmony, regal menace, no vocals and no recognizable franchise themes",
      archetypes: [
        a(
          "symphonic-assault", "Штурм чёрной цитадели",
          "fast string ostinato, pipe organ, low brass, distorted rhythm guitar and hard live drums, decisive orchestral-rock climax"
        ),
        a(
          "villain-cabaret", "Бал безумного владыки",
          "crooked swing pulse, upright piano, brass stabs, harpsichord flecks, elastic electronic bass and playful sinister turns"
        ),
        a(
          "arcane-machine", "Магическая машина войны",
          "industrial electronic pulse, granular bass, sharp orchestral stabs, syncopated drums and rapid tension-release contrasts"
        ),
        a(
          "royal-ritual", "Ритуал тёмной короны",
          "ritual toms and crisp snare, pipe organ, bright trumpet stabs, rapid high-string ostinato, monumental march with a forceful full-band peak"
        ),
        a(
          "black-elegy", "Элегия последнего трона",
          "somber piano, cold electronic heartbeat, lyrical strings, clear cymbal detail and a bright guitar-led final surge"
        ),
        a(
          "conquest", "Марш великого завоевания",
          "bold brass calls, double-time drums, racing strings, dark synthesizer layers and a triumphant yet threatening finale"
        ),
      ]
    ),
    "Pirate": Definition(
      base:
        "instrumental age-of-sail adventure music, strong nautical identity, human acoustic pulse and cinematic scale, no singing",
      archetypes: [
        a(
          "shanty", "Морская артель",
          "about 124 to 132 BPM, concertina and fiddle exchange a call-and-response melody without voice, stomping deck rhythm, frequent folk cadences"
        ),
        a(
          "battle", "Бортовой залп",
          "naval brass, urgent strings, low war drums, bold minor-mode battle theme"),
        a(
          "tavern", "Портовая таверна",
          "fiddle jig, concertina, bodhran, wooden percussion, tipsy syncopation"),
        a(
          "storm", "Погоня сквозь шторм",
          "galloping dotted string ostinato, thunderous toms, bold brass swells, sharp minor-mode turns, rising sea-danger arc"
        ),
        a(
          "ghost-ship", "Корабль-призрак",
          "hurdy-gurdy drone, bowed bass, distant bells, dark modal sea legend"),
        a(
          "treasure", "Остров сокровищ",
          "plucked strings, hand percussion, curious whistle melody, adventurous brass"),
        a(
          "coast", "Ветер архипелага", "fiddle, wooden flute, frame drum, bright coastal folk dance"
        ),
        a(
          "cinematic-suite", "Легенда семи морей",
          "layered strings and horns, broad three-part adventure arc, quiet oceanic middle section and a powerful minor-to-major return"
        ),
      ]
    ),
    "Rock": Definition(
      base:
        "instrumental live rock band, human dynamics, electric guitars, bass and acoustic drum kit",
      archetypes: [
        a("classic", "Открытая трасса", "crunchy rhythm guitars, melodic lead hook, roomy drums"),
        a(
          "alternative", "Альтернативная сцена",
          "clean delayed verse guitar, overdriven chorus, melodic bass"),
        a(
          "anime-00s", "Аниме-рок нулевых",
          "about 136 BPM, jangly octave guitar, melodic counterpoint bass, punchy acoustic kit, compact verse motion and a bright fuzzy climax"
        ),
        a("garage", "Гаражный импульс", "raw compact riff, loose punchy drums, dry room sound"),
        a("desert", "Пыльный усилитель", "low fuzzy guitar, hypnotic bass groove, wide toms"),
      ]
    ),
    "Metal": Definition(
      base:
        "instrumental heavy metal, powerful bass, live drums, articulate distorted guitars, no vocals",
      archetypes: [
        a(
          "heavy", "Стальной прилив", "down-tuned riffs, tight double kick, harmonized lead guitars"
        ),
        a(
          "doom", "Каменный колокол",
          "massive slow riffs, dark bass, spacious toms, ominous sustain"),
        a(
          "progressive", "Ломаная кузница",
          "syncopated riffs, changing meter, precise drums, melodic climax"),
        a(
          "symphonic", "Железная корона",
          "orchestral brass and strings around a heavy guitar foundation"),
        a(
          "melodic", "Северное лезвие", "tremolo melody, galloping rhythm, clear twin-guitar theme"),
      ]
    ),
    "Thrash Metal": Definition(
      base: "instrumental thrash metal, relentless live performance, sharp stops, no vocals",
      archetypes: [
        a("classic", "Ржавый вихрь", "fast palm-muted riffs, galloping bass, aggressive snare"),
        a(
          "technical", "Точный удар",
          "angular chromatic riffs, alternate picking, precise meter shifts"),
        a(
          "mosh", "Круговая атака", "compact mosh riffs, abrupt half-time drops, rapid power chords"
        ),
        a(
          "speed", "Без тормозов", "speed-metal momentum, double kick, short harmonized guitar solo"
        ),
        a(
          "dark", "Чёрный реактор", "dissonant riff cells, low-register tremolo, tense drum breaks"),
      ]
    ),
    "Cute": Definition(
      base: "cute playful instrumental, bright harmony, small-scale textures, no vocals",
      archetypes: [
        a("storybook", "Плюшевая сказка", "toy piano, pizzicato strings, glockenspiel, tiny drums"),
        a("kawaii", "Карамельный синт", "bubbly synthesizer bass, chiptune lead, handclaps"),
        a("music-box", "Шкатулка", "music box, soft marimba, little bell accents"),
        a("picnic", "Солнечный пикник", "ukulele, whistles as instruments, brushed percussion"),
        a(
          "tiny-quest", "Маленький квест",
          "playful flutes, plucked strings, gentle adventure rhythm"),
      ]
    ),
    "Chaos": Definition(
      base:
        "controlled experimental instrumental chaos, recurring motif, structured tension and release",
      archetypes: [
        a("polymeter", "Сломанный метр", "polymetric drums, dissonant brass bursts, angular bass"),
        a(
          "prepared", "Препарированный рояль",
          "prepared piano, noisy percussion, sudden dynamic cuts"),
        a(
          "glitch", "Ошибка сигнала",
          "sliced rhythms, unstable synth pitch, distorted digital texture"),
        a(
          "orchestral", "Оркестр на грани",
          "clustered strings, brass smears, violent percussion contrasts"),
        a("collage", "Радио из осколков", "genre fragments, tape edits, one unifying pulse"),
      ]
    ),
    "Electronic": Definition(
      base:
        "instrumental electronic production, detailed stereo field, clean low end, evolving sound design",
      archetypes: [
        a("analog", "Аналоговый ток", "sequenced arpeggios, drum machine, deep synth bass"),
        a("downtempo", "Медленный контур", "syncopated beat, glassy plucks, warm sub bass"),
        a(
          "melodic", "Световой импульс",
          "layered synth theme, pulsing bass, clear build and release"),
        a("idm", "Умная машина", "intricate micro-rhythm, crystalline tones, asymmetrical details"),
        a(
          "organic", "Живая электроника",
          "processed hand percussion, wooden plucks, soft modular pulse"),
      ]
    ),
    "Synthwave": Definition(
      base:
        "instrumental retro-futurist synthwave, analog synthesizers, cinematic night atmosphere",
      archetypes: [
        a(
          "neon", "Неоновое шоссе", "poly-synth chords, gated snare, arpeggiated bass, bright lead"),
        a("dark", "Ночной протокол", "heavy electronic drums, minor pads, tense driving sequencer"),
        a("dream", "Пурпурный сон", "soft vintage pads, chorus guitar, glowing bass pulse"),
        a("arcade", "Аркадная погоня", "punchy bass sequence, digital lead, compact action form"),
        a(
          "cinematic", "Город после дождя", "wide pads, slow lead melody, reflective neon ambience"),
      ]
    ),
    "House": Definition(
      base:
        "instrumental house, four-on-the-floor kick, syncopated bass, polished club arrangement",
      archetypes: [
        a("deep", "Глубокий клуб", "warm sub bass, shuffled percussion, soulful electric piano"),
        a("disco", "Зеркальный шар", "filtered rhythm guitar, elastic bass, bright strings"),
        a("piano", "Клавиши на крыше", "piano stabs, crisp hats, uplifting chord loop"),
        a("minimal", "Чистые четыре", "dry kick, tiny percussion shifts, restrained chord stab"),
        a("organic", "Тёплый двор", "hand percussion, plucked motif, rounded bass groove"),
      ]
    ),
    "Techno": Definition(
      base:
        "instrumental techno, repetitive four-on-the-floor drive, minimal harmony, evolving filters",
      archetypes: [
        a(
          "hypnotic", "Гипноз тоннеля",
          "rolling low end, metallic percussion, slowly shifting motif"),
        a(
          "detroit", "Машинный фанк",
          "futuristic chord stabs, syncopated machine drums, spacious delay"),
        a("dub", "Эхо бетона", "deep chord echoes, sub pressure, sparse percussion"),
        a("driving", "Ночная магистраль", "firm kick, tom propulsion, austere two-note sequence"),
        a(
          "minimal", "Малый механизм",
          "precise click percussion, dry bass pulse, microscopic change"),
      ]
    ),
    "Hard Techno": Definition(
      base:
        "instrumental hard techno, roughly 140 to 154 BPM warehouse pressure, high onset density, forceful kick, controlled distortion",
      archetypes: [
        a("raw", "Сырая комната", "raw rumble, clipped percussion, stark minor stab"),
        a(
          "schranz", "Стальной шранц",
          "hammering kick, looped industrial percussion, relentless momentum"),
        a(
          "groove", "Тяжёлый грув",
          "rolling tom groove, syncopated low-end accents, short rave signal"),
        a("trance", "Жёсткий транс", "driving bass, dark trance arpeggio, tense release"),
        a(
          "hi-tech", "Красная зона",
          "rapid precision drums, futuristic alarm motif, dense energy arc"),
      ]
    ),
    "Industrial Techno": Definition(
      base:
        "instrumental industrial techno, 148 to 160 BPM mechanical pressure with occasional faster peaks, bright abrasive detail, dark club production, no vocals",
      archetypes: [
        a("factory", "Машинный цех", "metal impacts, piston rhythm, distorted rumbling bass"),
        a(
          "cyber-goth", "Кибер-готика",
          "cold synth choir texture without voices, hard kick, ominous arpeggio"),
        a("ritual", "Ритуал из стали", "tribal toms, found-metal percussion, low drone"),
        a(
          "noise", "Белый жар",
          "controlled noise walls, power-electronic pulses, recurring kick anchor"),
        a(
          "broken", "Сломанный конвейер",
          "off-grid machine hits, broken beat inserts, dark bass pressure"),
      ]
    ),
    "Hardcore": Definition(
      base:
        "instrumental hardcore electronic music, 160 to 190 BPM continuous high energy, dense transients, hard clipped kick, no vocals",
      archetypes: [
        a("gabber", "Габбер-удар", "distorted tail kick, rapid hats, brutal simple hook"),
        a(
          "industrial", "Индустриальное ядро", "metallic percussion, dark drone, punishing low end"),
        a("melodic", "Свет сквозь шум", "hard kick under a clear minor-key rave melody"),
        a("breakcore", "Ломаное ядро", "hyper-edited breaks, sub drops, controlled rhythmic chaos"),
        a(
          "warehouse", "Аварийный строб",
          "siren-like synth as instrument, relentless pulse, abrupt stops"),
      ]
    ),
    "Psytrance": Definition(
      base: "instrumental psytrance, rolling offbeat bass, precise kick, psychedelic sound design",
      archetypes: [
        a("forest", "Ночной лес", "organic clicks, dark drones, twisting resonant sequence"),
        a(
          "goa", "Солнечная спираль", "layered acid melody, bright arpeggios, long evolving journey"
        ),
        a(
          "progressive", "Ровная орбита",
          "clean bass pulse, spacious effects, patient melodic reveal"),
        a(
          "dark", "Чёрный портал",
          "dissonant synth creatures, dense percussion, ominous low atmosphere"),
        a(
          "hi-tech", "Квантовый разгон",
          "rapid digital motifs, micro-edits, precise high-speed build"),
      ]
    ),
    "Breakbeat": Definition(
      base: "instrumental breakbeat, syncopated broken drums, strong bass movement, no vocals",
      archetypes: [
        a("big-beat", "Большой бит", "chunky sampled drums, distorted bass riff, swaggering hook"),
        a("uk-breaks", "Ночной брейкс", "tight shuffled breaks, sub bass, futuristic chord stab"),
        a("electro", "Электроразряд", "robotic syncopation, analog bass, sharp snare accents"),
        a("rave", "Ломаный рейв", "chopped break, rave piano fragments, elastic bass"),
        a(
          "cinematic", "Погоня по крышам",
          "layered break drums, orchestral tension pulse, wide climax"),
      ]
    ),
    "Drum and Bass": Definition(
      base:
        "instrumental drum and bass, fast chopped breakbeats, precise sub bass, powerful clean mix",
      archetypes: [
        a("liquid", "Жидкий свет", "warm bass, jazz-inflected electric piano, airy pads"),
        a("neuro", "Нейронный бас", "modulated Reese bass, intricate edits, tense ambience"),
        a("jungle", "Городские джунгли", "raw amen-style break language, deep sub, dub echoes"),
        a("dancefloor", "Большой разгон", "bright hook, firm drop, energetic rolling drums"),
        a(
          "atmospheric", "Высотный поток",
          "wide cinematic pads, detailed breaks, emotional progression"),
      ]
    ),
    "Cyberpunk": Definition(
      base:
        "instrumental eclectic dark-future city radio, bright dense production, moderate dynamics, technology and street energy, no copyrighted samples",
      archetypes: [
        a(
          "industrial-rock", "Радио индустриального рока",
          "distorted guitar machines, electronic drums, hostile bass riff"),
        a(
          "dark-club", "Радио тёмного клуба",
          "acidic 124 to 132 BPM electro pulse, cold synths, industrial percussion and slowly mutating filters"
        ),
        a(
          "future-hop", "Радио улиц будущего", "heavy 808, broken trap drums, granular city texture"
        ),
        a(
          "neon-pop", "Радио неоновой ночи",
          "glossy chopped-synth motif, bittersweet chords, punchy electronic beat and a wide emotional breakdown"
        ),
        a(
          "street-club", "Радио уличного клуба",
          "syncopated dembow-like percussion without vocals, distorted sub bass, synthetic brass accents and restless urban motion"
        ),
        a(
          "combat", "Радио боевого сектора",
          "drum-and-bass propulsion, metal accents, alarm-like motif"),
        a(
          "dark-ambient", "Радио пустошей",
          "dark ambient drones, distant machinery, sparse sub pulses"),
        a(
          "future-jazz", "Радио хромового джаза",
          "muted electric horn timbre, broken drums, synthetic upright bass"),
        a(
          "chrome-metal", "Радио хром-метала",
          "down-tuned guitar, electronic kick layers, mechanical riff cycle"),
      ]
    ),
    "Hip-hop": Definition(
      base:
        "instrumental hip-hop, strong pocket, no rap and no voice, original unsampled performance",
      archetypes: [
        a("boom-bap", "Виниловый шаг", "soulful chords, swung kick and snare, warm bassline"),
        a(
          "jazz", "Ночной квартал",
          "upright bass, Rhodes piano, dusty breakbeat, horn-like synth flecks"),
        a("trap", "Глубокий 808", "crisp hi-hat patterns, sparse minor keys, cinematic drums"),
        a("abstract", "Бит из теней", "uneven sample-like textures, low pulse, mysterious motif"),
        a("funk", "Карманный рэп-бит", "syncopated bass, clavinet, tight dry drums"),
      ]
    ),
    "Funk": Definition(
      base:
        "instrumental funk, syncopated bass, tight live drum pocket, playful call-and-response instruments",
      archetypes: [
        a("classic", "Медный шаг", "muted rhythm guitar, clavinet, sharp brass punches"),
        a("deep", "Глубокий карман", "dry drums, wah guitar, organ stabs, melodic bass fills"),
        a("electro", "Электрофанк", "slap bass, analog synth lead, handclaps"),
        a(
          "phantom", "Фантомный фанк",
          "about 112 BPM, ghostly jazz-fusion, electric piano, nimble syncopated bass, crisp drums, playful spectral synths and strong dynamic contrasts"
        ),
        a("city-pop", "Городской блеск", "clean guitar, polished bass, bright jazz-pop chords"),
        a(
          "jrpg", "Приключенческий фьюжн",
          "frequent colorful harmonic turns, slap bass, electric piano, animated lead synth and a clear breakdown-to-rebuild arc"
        ),
        a(
          "boss-fusion", "Фанковая битва с призраком",
          "bright electric piano runs, elastic bass counterpoint, tight live drums, spectral synthesizer answers and theatrical fusion climax"
        ),
      ]
    ),
    "Jazz": Definition(
      base: "instrumental jazz, natural ensemble interaction, acoustic detail, no vocals",
      archetypes: [
        a("trio", "Ночной трио", "swinging ride, upright walking bass, piano improvisation"),
        a("cool", "Синий час", "brushed drums, muted trumpet, spacious piano voicings"),
        a("modal", "Открытый лад", "tenor saxophone, quartal piano, extended modal development"),
        a(
          "fusion", "Игровой джаз-фьюжн",
          "electric piano, melodic syncopated bass, crisp drums, colorful game-fusion harmony and energetic sectional contrasts"
        ),
        a(
          "spectral-fusion", "Призрачный джаз-фьюжн",
          "electric piano improvisation, nimble bass, bright drum accents, playful spectral synthesizer and a dramatic harmonic turnaround"
        ),
        a(
          "cabaret", "Полуночное кабаре",
          "upright piano, clarinet, brushed kit, theatrical minor harmony"),
      ]
    ),
    "Classical": Definition(
      base: "instrumental classical music, realistic acoustic performance, clear voice leading",
      archetypes: [
        a(
          "baroque", "Барочная зала",
          "contrapuntal strings, harpsichord continuo, elegant articulation"),
        a("quartet", "Камерный разговор", "string quartet, balanced thematic development"),
        a("romantic", "Романтическая сцена", "lyrical strings, woodwind color, broad dynamics"),
        a("piano", "Один рояль", "concert grand piano, expressive rubato, coherent recital form"),
        a(
          "modern", "Современная палата",
          "transparent dissonance, precise chamber textures, unusual meter"),
      ]
    ),
    "Post-rock": Definition(
      base: "instrumental post-rock, patient motif development, expansive live band dynamics",
      archetypes: [
        a(
          "crescendo", "Долгий подъём",
          "clean delayed guitars, spacious drums, wide distortion finale"),
        a("atmospheric", "Море антенн", "tremolo layers, bowed textures, slow tom pattern"),
        a("minimal", "Один маяк", "repeating guitar figure, warm bass, restrained kit"),
        a("heavy", "Свет после бури", "low guitar wall, huge drums, cathartic melodic release"),
        a(
          "electronic", "Сигналы вдали", "post-rock guitars with subtle sequencer and granular air"),
      ]
    ),
    "Cinematic": Definition(
      base:
        "instrumental cinematic score, clear narrative arc, realistic orchestration, no trailer voice",
      archetypes: [
        a("adventure", "Большая дорога", "string theme, noble brass, orchestral percussion"),
        a("intimate", "Тихий кадр", "felt piano, chamber strings, subtle pulse"),
        a("epic", "Перед битвой", "low ostinato, broad horns, large drums, triumphant resolution"),
        a(
          "thriller", "Часы в темноте", "ticking percussion, tense strings, low electronic pressure"
        ),
        a(
          "wonder", "Неизвестный мир",
          "woodwind colors, luminous strings, gradual sense of discovery"),
      ]
    ),
  ]

  private static let fallbackPresets = makePresets(for: fallback)
  private static let presetCatalog = definitions.mapValues(makePresets)

  private static func mix(_ input: UInt64) -> UInt64 {
    var value = input &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
