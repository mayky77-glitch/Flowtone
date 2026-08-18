'use strict';

// Mirrors the 350 macOS production profiles from GenrePromptCatalog.
const PROFILE_CATALOG = {
  Ambient: {
    base: 'ambient instrumental, spacious natural reverb, slow harmonic movement, no drums',
    details: [
      'evolving analog pads, low drone, sparse felt piano',
      'breathy woodwinds, bowed textures, gentle overtones',
      'granular air, distant chimes, dark subharmonic bed',
      'slow tidal swells, glass harmonics, wide stereo space',
      'weightless synthesizer layers, subtle pulses, luminous upper partials',
    ],
  },
  'Lo-fi': {
    base: 'lo-fi instrumental, warm cassette texture, relaxed pocket, intimate room sound',
    details: [
      'dusty boom-bap drums, mellow Rhodes chords, rounded bass',
      'muted piano loop, brushed drums, rain-like tape hiss',
      'sampled jazz guitar, upright-like bass, soft swung snare',
      'music-box fragment, lazy breakbeat, neighborhood ambience',
      'electric piano, nylon guitar flecks, warm side-chained pads',
    ],
  },
  'Light Rave': {
    base: 'instrumental Berlin rave and hard-dance continuum, elastic club low end, bright detailed top end, continuous dance-floor motion, no crowd and no vocals',
    details: [
      '112 to 124 BPM body-moving groove, raw room drums, rolling bass, concise trance stabs, long blend-friendly development',
      'bouncy hard-dance bass, bright rave chords, playful syncopation, crisp rapid percussion',
      'euphoric trance arpeggio, brief piano lift, airy breakdown, quick return to the kick',
      'restrained acid sequence, crisp hats, warm filtered build, rounded kick without harsh clipping',
      'short breakbeat accents inside a steady pulse, elastic bass, compact rave-synth hook',
      'tribal rolling drums, syncopated toms, short metallic loop, dense sixteenth-note motion',
      'bright supersaw chord, galloping bass, playful retro dance motif, controlled euphoric peak',
    ],
  },
  Fantasy: {
    base: 'instrumental historical fantasy score, modal melody, realistic acoustic orchestration, ancient world atmosphere',
    details: [
      'noble horns, sweeping strings, frame drums, lute and hammered dulcimer',
      'celesta, harp harmonics, glockenspiel, breathy flutes, mysterious magic',
      'bold brass calls, urgent string ostinato, war drums, triumphant finale',
      'slow Nordic modal motif, open fifths, low strings, solo horn and wooden flute, very wide dynamics, mountain stillness',
      'low bowed strings and brass shaped like a distant ceremonial chorus without voices, stone reverb, patient modal harmony',
      'broad low horns, forceful orchestral unison, large frame drums, urgent strings, heroic ascent from sparse wilderness',
      'bone-flute timbre, primitive plucked strings, stone echoes, elemental mystery',
      'bass clarinet, low strings, distant brass, tense ritual pulse',
      'lute, fiddle, hand drum, wooden flute, lively medieval dance',
    ],
  },
  'Dark Empire': {
    base: 'instrumental dark imperial fantasy, vivid full-spectrum theatrical production, punchy drums, crisp upper strings and brass, chromatic minor harmony, regal menace, no vocals and no recognizable franchise themes',
    details: [
      'fast string ostinato, pipe organ, low brass, distorted rhythm guitar and hard live drums, decisive orchestral-rock climax',
      'crooked swing pulse, upright piano, brass stabs, harpsichord flecks, elastic electronic bass and playful sinister turns',
      'industrial electronic pulse, granular bass, sharp orchestral stabs, syncopated drums and rapid tension-release contrasts',
      'ritual toms and crisp snare, pipe organ, bright trumpet stabs, rapid high-string ostinato, monumental march with a forceful full-band peak',
      'somber piano, cold electronic heartbeat, lyrical strings, clear cymbal detail and a bright guitar-led final surge',
      'bold brass calls, double-time drums, racing strings, dark synthesizer layers and a triumphant yet threatening finale',
    ],
  },
  Pirate: {
    base: 'instrumental lively sea-song and shanty folk, simple catchy diatonic or Dorian melody, short repeated refrain, steady deck-work pulse, bright communal energy, small dry acoustic ensemble only, no vocals and no symphonic orchestra',
    details: [
      'about 124 to 132 BPM in plain 4/4, a four-chord folk loop, solo fiddle question answered by concertina and tin-whistle unison, boot stomp on every beat, handclap backbeat, immediate eight-bar hook',
      'about 104 to 116 BPM, circular capstan rhythm in steady 4/4, repeating concertina figure, warm fiddle refrain, low frame-drum beat and an uncomplicated homeward melody',
      'about 116 to 128 BPM in firm 2/4, short fiddle call followed by two accented ensemble answers, wooden percussion, boot heels and clear tonic-dominant folk cadences',
      'about 128 to 140 BPM, playful Dorian hand-over-hand pulse, compact two-bar fiddle phrase answered by whistle and concertina, swinging stomps and a rowdy but tidy refrain',
      'about 108 to 120 BPM, plain storytelling fiddle melody, acoustic guitar downstrokes, concertina response, a memorable recurring refrain and gentle human timing',
      'about 116 to 128 BPM, jaunty dotted hornpipe rhythm, major-key AABB form, fiddle and tin whistle in unison, light bodhran and heel taps',
      'about 112 to 124 BPM, bright Mixolydian folk tune, rising fiddle lead answered by concertina chords, claps and a broad singalong-shaped instrumental refrain',
      'about 96 to 112 BPM in lilting 6/8, two-beat rowing sway, low frame drum, plucked acoustic guitar, simple wooden-flute call and a repeated fiddle answer',
    ],
  },
  Rock: {
    base: 'instrumental live rock band, human dynamics, electric guitars, bass and acoustic drum kit',
    details: [
      'crunchy rhythm guitars, melodic lead hook, roomy drums',
      'clean delayed verse guitar, overdriven chorus, melodic bass',
      'about 136 BPM, jangly octave guitar, melodic counterpoint bass, punchy acoustic kit, compact verse motion and a bright fuzzy climax',
      'raw compact riff, loose punchy drums, dry room sound',
      'low fuzzy guitar, hypnotic bass groove, wide toms',
    ],
  },
  Metal: {
    base: 'instrumental heavy metal, powerful bass, live drums, articulate distorted guitars, no vocals',
    details: [
      'down-tuned riffs, tight double kick, harmonized lead guitars',
      'massive slow riffs, dark bass, spacious toms, ominous sustain',
      'syncopated riffs, changing meter, precise drums, melodic climax',
      'orchestral brass and strings around a heavy guitar foundation',
      'tremolo melody, galloping rhythm, clear twin-guitar theme',
    ],
  },
  'Thrash Metal': {
    base: 'instrumental thrash metal, relentless live performance, sharp stops, no vocals',
    details: [
      'fast palm-muted riffs, galloping bass, aggressive snare',
      'angular chromatic riffs, alternate picking, precise meter shifts',
      'compact mosh riffs, abrupt half-time drops, rapid power chords',
      'speed-metal momentum, double kick, short harmonized guitar solo',
      'dissonant riff cells, low-register tremolo, tense drum breaks',
    ],
  },
  Cute: {
    base: 'cute playful instrumental, bright harmony, small-scale textures, no vocals',
    details: [
      'toy piano, pizzicato strings, glockenspiel, tiny drums',
      'bubbly synthesizer bass, chiptune lead, handclaps',
      'music box, soft marimba, little bell accents',
      'ukulele, whistles as instruments, brushed percussion',
      'playful flutes, plucked strings, gentle adventure rhythm',
    ],
  },
  Chaos: {
    base: 'controlled experimental instrumental chaos, recurring motif, structured tension and release',
    details: [
      'polymetric drums, dissonant brass bursts, angular bass',
      'prepared piano, noisy percussion, sudden dynamic cuts',
      'sliced rhythms, unstable synth pitch, distorted digital texture',
      'clustered strings, brass smears, violent percussion contrasts',
      'genre fragments, tape edits, one unifying pulse',
    ],
  },
  Electronic: {
    base: 'instrumental electronic production, detailed stereo field, clean low end, evolving sound design',
    details: [
      'sequenced arpeggios, drum machine, deep synth bass',
      'syncopated beat, glassy plucks, warm sub bass',
      'layered synth theme, pulsing bass, clear build and release',
      'intricate micro-rhythm, crystalline tones, asymmetrical details',
      'processed hand percussion, wooden plucks, soft modular pulse',
    ],
  },
  Synthwave: {
    base: 'instrumental retro-futurist analog synth noir, expressive polyphonic synth brass, simple memorable motif, wide dimensional reverb, tactile low-frequency design, human emotion inside a vast technological space, no vocals and no recognizable film themes',
    details: [
      'poly-synth chords, gated snare, arpeggiated bass, bright lead',
      'heavy electronic drums, minor pads, tense driving sequencer',
      'soft vintage pads, chorus guitar, glowing bass pulse',
      'punchy bass sequence, digital lead, compact action form',
      'wide pads, slow lead melody, reflective neon ambience',
      'a lone processed piano note gives way to one immense detuned synth-brass chord, then sparse low pulses and long breathing gaps',
      'warm unstable analog pad, fragile three-note lead, soft rain-like high-frequency texture, slow harmonic changes and an intimate restrained pulse',
      'granular glass harmonics, filtered clockwork arpeggio, muted electric piano, deep room tone and a small motif gradually revealed by timbre',
      'slow mechanical impacts, distorted sub-bass pressure, scraped metallic texture, narrow minor-second signal and controlled industrial escalation',
      'dry wind-like noise, distant low synth horn, isolated percussion hit, enormous empty stereo field and a patient two-chord progression',
      'majestic polyphonic analog brass, slow parallel chord movement, massive reverberant tail, quiet sub drone and one clear rising human-scale theme',
      'soft chorus-rich poly synth, breathy monophonic lead, low heartbeat pulse, suspended harmony and a tender minimal refrain without drums',
      'claustrophobic repeating synth cell, clipped electronic knocks, rising filtered noise, dissonant interruptions and abrupt pockets of near-silence',
      'motoric low sequencer, pulsing noise rhythm, broad synth-brass calls, accelerating layered ostinato and a sharply focused electronic peak',
      'long-form bass pulse, tidal waves of synth brass, sparse heavy percussion, a simple emotional lead entering late and a monumental final release',
    ],
  },
  House: {
    base: 'instrumental house, four-on-the-floor kick, syncopated bass, polished club arrangement',
    details: [
      'warm sub bass, shuffled percussion, soulful electric piano',
      'filtered rhythm guitar, elastic bass, bright strings',
      'piano stabs, crisp hats, uplifting chord loop',
      'dry kick, tiny percussion shifts, restrained chord stab',
      'hand percussion, plucked motif, rounded bass groove',
    ],
  },
  Techno: {
    base: 'instrumental techno, repetitive four-on-the-floor drive, minimal harmony, evolving filters',
    details: [
      'rolling low end, metallic percussion, slowly shifting motif',
      'futuristic chord stabs, syncopated machine drums, spacious delay',
      'deep chord echoes, sub pressure, sparse percussion',
      'firm kick, tom propulsion, austere two-note sequence',
      'precise click percussion, dry bass pulse, microscopic change',
    ],
  },
  'Hard Techno': {
    base: 'instrumental hard techno, roughly 140 to 154 BPM warehouse pressure, high onset density, forceful kick, controlled distortion',
    details: [
      'raw rumble, clipped percussion, stark minor stab',
      'hammering kick, looped industrial percussion, relentless momentum',
      'rolling tom groove, syncopated low-end accents, short rave signal',
      'driving bass, dark trance arpeggio, tense release',
      'rapid precision drums, futuristic alarm motif, dense energy arc',
    ],
  },
  'Industrial Techno': {
    base: 'instrumental industrial techno, 148 to 160 BPM mechanical pressure with occasional faster peaks, bright abrasive detail, dark club production, no vocals',
    details: [
      'metal impacts, piston rhythm, distorted rumbling bass',
      'cold synth choir texture without voices, hard kick, ominous arpeggio',
      'tribal toms, found-metal percussion, low drone',
      'controlled noise walls, power-electronic pulses, recurring kick anchor',
      'off-grid machine hits, broken beat inserts, dark bass pressure',
    ],
  },
  Hardcore: {
    base: 'instrumental hardcore electronic music, 160 to 190 BPM continuous high energy, dense transients, hard clipped kick, no vocals',
    details: [
      'distorted tail kick, rapid hats, brutal simple hook',
      'metallic percussion, dark drone, punishing low end',
      'hard kick under a clear minor-key rave melody',
      'hyper-edited breaks, sub drops, controlled rhythmic chaos',
      'siren-like synth as instrument, relentless pulse, abrupt stops',
    ],
  },
  Psytrance: {
    base: 'instrumental psytrance, rolling offbeat bass, precise kick, psychedelic sound design',
    details: [
      'organic clicks, dark drones, twisting resonant sequence',
      'layered acid melody, bright arpeggios, long evolving journey',
      'clean bass pulse, spacious effects, patient melodic reveal',
      'dissonant synth creatures, dense percussion, ominous low atmosphere',
      'rapid digital motifs, micro-edits, precise high-speed build',
    ],
  },
  Breakbeat: {
    base: 'instrumental breakbeat, syncopated broken drums, strong bass movement, no vocals',
    details: [
      'chunky sampled drums, distorted bass riff, swaggering hook',
      'tight shuffled breaks, sub bass, futuristic chord stab',
      'robotic syncopation, analog bass, sharp snare accents',
      'chopped break, rave piano fragments, elastic bass',
      'layered break drums, orchestral tension pulse, wide climax',
    ],
  },
  'Drum and Bass': {
    base: 'instrumental drum and bass, fast chopped breakbeats, precise sub bass, powerful clean mix',
    details: [
      'warm bass, jazz-inflected electric piano, airy pads',
      'modulated Reese bass, intricate edits, tense ambience',
      'raw amen-style break language, deep sub, dub echoes',
      'bright hook, firm drop, energetic rolling drums',
      'wide cinematic pads, detailed breaks, emotional progression',
    ],
  },
  Cyberpunk: {
    base: 'instrumental eclectic dark-future city radio, bright dense production, moderate dynamics, technology and street energy, no copyrighted samples',
    details: [
      'distorted guitar machines, electronic drums, hostile bass riff',
      'acidic 124 to 132 BPM electro pulse, cold synths, industrial percussion and slowly mutating filters',
      'heavy 808, broken trap drums, granular city texture',
      'glossy chopped-synth motif, bittersweet chords, punchy electronic beat and a wide emotional breakdown',
      'syncopated dembow-like percussion without vocals, distorted sub bass, synthetic brass accents and restless urban motion',
      'drum-and-bass propulsion, metal accents, alarm-like motif',
      'dark ambient drones, distant machinery, sparse sub pulses',
      'muted electric horn timbre, broken drums, synthetic upright bass',
      'down-tuned guitar, electronic kick layers, mechanical riff cycle',
    ],
  },
  'Hip-hop': {
    base: 'instrumental hip-hop, strong pocket, no rap and no voice, original unsampled performance',
    details: [
      'soulful chords, swung kick and snare, warm bassline',
      'upright bass, Rhodes piano, dusty breakbeat, horn-like synth flecks',
      'crisp hi-hat patterns, sparse minor keys, cinematic drums',
      'uneven sample-like textures, low pulse, mysterious motif',
      'syncopated bass, clavinet, tight dry drums',
    ],
  },
  Funk: {
    base: 'instrumental funk, syncopated bass, tight live drum pocket, playful call-and-response instruments',
    details: [
      'muted rhythm guitar, clavinet, sharp brass punches',
      'dry drums, wah guitar, organ stabs, melodic bass fills',
      'slap bass, analog synth lead, handclaps',
      'about 112 BPM, ghostly jazz-fusion, electric piano, nimble syncopated bass, crisp drums, playful spectral synths and strong dynamic contrasts',
      'clean guitar, polished bass, bright jazz-pop chords',
      'frequent colorful harmonic turns, slap bass, electric piano, animated lead synth and a clear breakdown-to-rebuild arc',
      'bright electric piano runs, elastic bass counterpoint, tight live drums, spectral synthesizer answers and theatrical fusion climax',
    ],
  },
  Jazz: {
    base: 'instrumental jazz, natural ensemble interaction, acoustic detail, no vocals',
    details: [
      'swinging ride, upright walking bass, piano improvisation',
      'brushed drums, muted trumpet, spacious piano voicings',
      'tenor saxophone, quartal piano, extended modal development',
      'electric piano, melodic syncopated bass, crisp drums, colorful game-fusion harmony and energetic sectional contrasts',
      'electric piano improvisation, nimble bass, bright drum accents, playful spectral synthesizer and a dramatic harmonic turnaround',
      'upright piano, clarinet, brushed kit, theatrical minor harmony',
    ],
  },
  Classical: {
    base: 'instrumental classical music, realistic acoustic performance, clear voice leading',
    details: [
      'contrapuntal strings, harpsichord continuo, elegant articulation',
      'string quartet, balanced thematic development',
      'lyrical strings, woodwind color, broad dynamics',
      'concert grand piano, expressive rubato, coherent recital form',
      'transparent dissonance, precise chamber textures, unusual meter',
    ],
  },
  'Post-rock': {
    base: 'instrumental post-rock, patient motif development, expansive live band dynamics',
    details: [
      'clean delayed guitars, spacious drums, wide distortion finale',
      'tremolo layers, bowed textures, slow tom pattern',
      'repeating guitar figure, warm bass, restrained kit',
      'low guitar wall, huge drums, cathartic melodic release',
      'post-rock guitars with subtle sequencer and granular air',
    ],
  },
  Cinematic: {
    base: 'instrumental cinematic score, clear narrative arc, realistic orchestration, no trailer voice',
    details: [
      'string theme, noble brass, orchestral percussion',
      'felt piano, chamber strings, subtle pulse',
      'low ostinato, broad horns, large drums, triumphant resolution',
      'ticking percussion, tense strings, low electronic pressure',
      'woodwind colors, luminous strings, gradual sense of discovery',
    ],
  },
  'Space Rock': {
    base: 'instrumental space rock, live psychedelic rock trio expanded by analog synthesizers, reverberant electric guitar, hypnotic otherworldly texture, human drums and bass, no vocals',
    details: [
      'steady motorik 4/4, repeating live bass figure, dotted-delay guitar and restrained modular pulses',
      'slow suspended live drums, volume-pedal guitar swells, vintage string-machine pad and wide breathing space',
      'energetic fuzzy guitar riff, sweeping phaser, assertive live kit and bright analog synthesizer flare',
      'minor-pentatonic guitar bends, patient live groove, analog organ chords and long tape echo',
      'clean guitar harmonics grow through stacked delays and tom patterns into one coherent post-rock crest',
      'analog sequencer, wah guitar, live bass and drums, gradual filter movement and a returning guitar theme',
      'accessible shifting meter, guitar and bass unison, vintage synthesizer answers and a concise dramatic arc',
      'memorable rock riff evolves through guitar and synthesizer exchanges before returning home with live-band dynamics',
    ],
  },
};

module.exports = { PROFILE_CATALOG };
