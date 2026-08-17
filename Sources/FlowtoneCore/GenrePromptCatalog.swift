import Foundation

/// Genre-specific production language for the local text-to-music model.
public struct GenrePromptCatalog: Sendable {
  public init() {}

  public func profile(for genre: String, seed: UInt64) -> String {
    let profiles = Self.profiles[genre] ?? [Self.fallback]
    return profiles[Int(Self.mix(seed) % UInt64(profiles.count))]
  }

  public func profileCount(for genre: String) -> Int {
    (Self.profiles[genre] ?? [Self.fallback]).count
  }

  private static let fallback =
    "instrumental ensemble, recognizable genre rhythm, natural dynamics, coherent musical development"

  private static let profiles: [String: [String]] = [
    "Ambient": [
      "ambient soundscape, evolving warm synthesizer pads, long drones, sparse piano, no drums, spacious natural reverb",
      "ambient minimalism, slow harmonic movement, granular air, soft field texture, restrained pulse, deep stereo space",
      "organic ambient, bowed textures, breathy woodwinds, low drone, gentle overtones, gradual development",
    ],
    "Lo-fi": [
      "lo-fi hip-hop instrumental, dusty boom-bap drums, mellow Rhodes chords, rounded bass, subtle tape flutter",
      "lo-fi study beat, sampled jazz guitar, soft kick and snare, relaxed swing, warm cassette texture",
      "lo-fi instrumental, muted piano loop, brushed drums, gentle sub bass, vinyl crackle, intimate room sound",
    ],
    "Light Rave": [
      "light euphoric rave instrumental, buoyant four-on-the-floor kick, piano stabs, bright arpeggios, airy breakdown",
      "melodic rave instrumental, crisp breakbeat accents, elastic bass, playful synth hook, warm sunrise energy",
      "soft warehouse rave, steady club kick, shimmering pads, restrained acid sequence, joyful gradual build",
    ],
    "Fantasy": [
      "majestic historical fantasy score, noble French horns, sweeping strings, frame drums, lute and hammered dulcimer, modal medieval melody, ancient kingdom atmosphere",
      "magical fantasy instrumental, celesta, harp harmonics, glockenspiel, breathy flutes and soft strings, mysterious enchanted forest, sparkling orchestration",
      "heroic fantasy score, bold brass calls, urgent string ostinato, large war drums, soaring modal theme, legendary quest and triumphant castle finale",
      "dark fantasy instrumental, low strings, bassoon, hurdy-gurdy drone, distant choir-like pads without voices, ritual drums, ruined fortress and ominous magic",
      "ancient cave fantasy ritual, deep frame drums, bone-flute timbre, primitive plucked strings, low drones, stone chamber echoes, forgotten runes and elemental magic",
    ],
    "Rock": [
      "rock instrumental, live acoustic drum kit, electric bass, crunchy rhythm guitars, memorable lead-guitar hook, human dynamics",
      "alternative rock instrumental, clean delayed guitar verse, overdriven chorus, melodic bass, roomy live drums",
      "garage rock instrumental, raw guitar riff, punchy bass, loose energetic drums, compact song form",
    ],
    "Metal": [
      "heavy metal instrumental, down-tuned distorted guitars, tight double-kick drums, powerful bass, harmonized lead guitars",
      "doom metal instrumental, massive slow guitar riffs, dark bass, spacious toms, ominous sustained harmony",
      "progressive metal instrumental, precise syncopated riffs, changing meter, articulate drums, melodic guitar climax",
    ],
    "Thrash Metal": [
      "thrash metal instrumental, very fast palm-muted low-string guitar riffs, galloping bass, relentless double-kick drums, sharp rhythmic stops",
      "classic thrash instrumental, rapid power-chord articulation, aggressive snare, tremolo-picked lead, compact mosh riff changes",
      "technical thrash metal instrumental, angular chromatic riffs, fast alternate picking, precise drums, short virtuosic guitar solo",
    ],
    "Cute": [
      "cute playful instrumental, toy piano, pizzicato strings, ukulele, glockenspiel, tiny bouncy drums, smiling melody",
      "kawaii electronic instrumental, bright chiptune lead, bubbly synthesizer bass, handclaps, candy-colored chord changes",
      "gentle cute music, music box, soft marimba, plucked strings, little bell accents, cozy storybook mood",
    ],
    "Chaos": [
      "controlled experimental chaos, polymetric drums, dissonant brass bursts, fractured electronic glitches, coherent rising arc",
      "avant-garde instrumental, irregular accents, prepared piano, noisy percussion, sudden contrasts connected by a recurring motif",
      "glitch chaos instrumental, sliced rhythms, unstable synthesizer pitch, distorted textures, deliberate tension and structured release",
    ],
    "Electronic": [
      "electronic instrumental, sequenced analog arpeggios, precise drum machine, deep synthesizer bass, evolving filtered hook",
      "downtempo electronica, syncopated beat, glassy synth plucks, warm sub bass, detailed atmospheric production",
      "melodic electronic instrumental, layered synthesizers, pulsing bass, crisp drums, clear verse-build-release structure",
    ],
    "Synthwave": [
      "synthwave instrumental, analog poly-synth chords, gated snare, arpeggiated bass, neon lead melody, cinematic 1980s production",
      "dark synthwave instrumental, driving sequencer, heavy electronic drums, minor-key pads, tense night-road atmosphere",
      "dreamwave instrumental, soft vintage synthesizers, chorus guitar, glowing bass pulse, nostalgic melodic hook",
    ],
    "House": [
      "house instrumental, four-on-the-floor kick, offbeat hi-hat, syncopated bassline, piano stabs, smooth club arrangement",
      "deep house instrumental, warm sub bass, shuffled percussion, soulful electric-piano chords, restrained hypnotic build",
      "disco house instrumental, filtered rhythm guitar, elastic bass, bright strings, crisp four-on-the-floor groove",
    ],
    "Techno": [
      "hypnotic techno instrumental, repetitive four-on-the-floor kick, minimal harmony, metallic percussion, slowly evolving filter movement",
      "Detroit-inspired techno instrumental, machine-funk drums, futuristic chord stabs, rolling bass sequence, spacious delay",
      "industrial techno instrumental, hard kick, rumbling low end, mechanical percussion, austere motif, controlled warehouse intensity",
    ],
    "Drum and Bass": [
      "drum and bass instrumental, fast chopped breakbeats, deep Reese bass, precise sub bass, atmospheric pads, energetic drops",
      "liquid drum and bass instrumental, rolling breakbeat, warm bass, jazz-inflected electric piano, airy melodic layers",
      "dark neuro drum and bass instrumental, intricate break edits, modulated bass design, tense ambience, clean powerful mix",
    ],
    "Hip-hop": [
      "boom-bap hip-hop instrumental, sampled soul chords, swung kick and snare, warm bassline, turntable texture, no rap",
      "jazz hip-hop instrumental, upright bass, Rhodes piano, dusty breakbeat, subtle horn fragments, relaxed pocket",
      "modern trap instrumental, deep 808 bass, crisp hi-hat patterns, sparse minor-key keys, cinematic drum accents, no vocals",
    ],
    "Funk": [
      "funk instrumental, syncopated electric bass, muted rhythm-guitar chanks, clavinet, tight drums, sharp brass punches",
      "deep funk instrumental, dry drum pocket, wah guitar, organ stabs, melodic bass fills, live-room energy",
      "electro-funk instrumental, slap bass, analog synth lead, handclaps, talk-box-like synth without voice, playful groove",
    ],
    "Jazz": [
      "acoustic jazz trio instrumental, swinging ride cymbal, upright bass walking line, piano improvisation, natural club-room dynamics",
      "cool jazz instrumental, brushed drums, muted trumpet, upright bass, spacious piano voicings, understated melodic improvisation",
      "modal jazz instrumental, tenor saxophone, driving ride cymbal, open quartal piano chords, extended organic development",
    ],
    "Classical": [
      "baroque classical instrumental, contrapuntal strings, harpsichord continuo, elegant voice leading, intimate chamber acoustics",
      "classical chamber music, string quartet, balanced sonata-like development, clear acoustic articulation, expressive dynamics",
      "romantic orchestral instrumental, lyrical strings, woodwind colors, noble brass, broad dynamic arc, concert-hall realism",
    ],
    "Post-rock": [
      "post-rock instrumental, clean delayed guitars, patient bass motif, spacious drums, long cinematic crescendo into wide distortion",
      "atmospheric post-rock, tremolo guitar layers, bowed textures, slow tom pattern, gradual emotional build and release",
      "minimal post-rock instrumental, repeating clean-guitar figure, warm bass, restrained kit, expansive cathartic finale",
    ],
    "Cinematic": [
      "cinematic instrumental score, narrative string theme, brass and orchestral percussion, clear dramatic arc, realistic orchestration",
      "intimate cinematic score, felt piano, chamber strings, subtle pulses, evolving emotional motif, detailed acoustic space",
      "epic cinematic instrumental, low string ostinato, broad horns, large drums, rising tension, memorable triumphant resolution",
    ],
  ]

  private static func mix(_ input: UInt64) -> UInt64 {
    var value = input &+ 0x9E37_79B9_7F4A_7C15
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
