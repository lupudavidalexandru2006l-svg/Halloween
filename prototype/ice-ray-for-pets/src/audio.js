// CLIENT: the Audio owner. Synth stand-ins named by event, so the port is a list of names
// to fill with sound ids in Config.sounds. Nothing is loud; music sits under the effects.
import { Config } from './config.js';

export function createAudio() {
  let ctx = null, master, sfxBus, musicBus;
  const state = { music: true, sfx: true, streak: 0, streakAt: 0, playing: {} };
  function ensure() {
    if (ctx) return true;
    try {
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      master = ctx.createGain(); master.gain.value = 0.9; master.connect(ctx.destination);
      sfxBus = ctx.createGain(); sfxBus.gain.value = Config.sounds.sfx * 0.5; sfxBus.connect(master);
      musicBus = ctx.createGain(); musicBus.gain.value = Config.sounds.music * 0.18; musicBus.connect(master);
      startMusic();
      return true;
    } catch { return false; }
  }
  function tone(freq, t0, dur, type = 'sine', vol = 0.5, bus = sfxBus, glideTo) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(freq, t0);
    if (glideTo) o.frequency.exponentialRampToValueAtTime(glideTo, t0 + dur);
    g.gain.setValueAtTime(0, t0); g.gain.linearRampToValueAtTime(vol, t0 + 0.01); g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
    o.connect(g); g.connect(bus); o.start(t0); o.stop(t0 + dur + 0.05);
  }
  function noise(t0, dur, vol = 0.2, hp = 1500) {
    const len = Math.floor(ctx.sampleRate * dur), buf = ctx.createBuffer(1, len, ctx.sampleRate), d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
    const s = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    f.type = 'highpass'; f.frequency.value = hp; g.gain.value = vol; s.buffer = buf; s.connect(f); f.connect(g); g.connect(sfxBus); s.start(t0);
  }
  const sounds = {
    click: (t) => tone(660, t, 0.06, 'triangle', 0.3),
    zap: (t) => tone(900, t, 0.25, 'sawtooth', 0.08, sfxBus, 1500),
    freeze: (t) => { noise(t, 0.35, 0.18, 3000); tone(1200, t, 0.3, 'sine', 0.25, sfxBus, 2400); },
    coin: (t, n = 0) => { const f = 880 * Math.pow(2, Math.min(n, 12) / 24); tone(f, t, 0.12, 'triangle', 0.28); tone(f * 1.5, t + 0.05, 0.12, 'triangle', 0.18); },
    // banking in a row climbs a step each time (Game Plan 16: rising chimes on streaks)
    bank: (t, n = 0) => { const k = Math.pow(2, Math.min(n, 8) / 12); noise(t, 0.2, 0.2, 2500); [523, 659, 784].forEach((f, i) => tone(f * k, t + 0.08 + i * 0.07, 0.25, 'triangle', 0.3)); },
    // rarer pets get a longer fanfare (rank 3 Rare .. 7 Secret)
    reveal_rare: (t, rank = 3) => [523, 659, 784, 1046, 1318, 1568, 2093].slice(0, Math.min(7, rank + 1)).forEach((f, i) => tone(f, t + i * 0.09, 0.4 + (i === rank ? 0.3 : 0), 'triangle', 0.3)),
    no: (t) => tone(260, t, 0.18, 'sine', 0.3, sfxBus, 190),
    buy: (t) => [660, 880, 1100].forEach((f, i) => tone(f, t + i * 0.06, 0.18, 'square', 0.12)),
    melt: (t) => tone(700, t, 0.5, 'sine', 0.22, sfxBus, 300),
    chill: (t) => [1046, 1318, 1568, 2093].forEach((f, i) => tone(f, t + i * 0.12, 0.6, 'sine', 0.18)),
    gift: (t) => [784, 988, 1175, 1568].forEach((f, i) => tone(f, t + i * 0.08, 0.3, 'triangle', 0.28)),
    unlock: (t) => [392, 523, 659, 784, 1046].forEach((f, i) => tone(f, t + i * 0.1, 0.45, 'triangle', 0.28)),
    bridge: (t) => { noise(t, 0.5, 0.15, 2000); tone(400, t, 0.5, 'sine', 0.2, sfxBus, 900); },
  };
  function play(name, n) {
    if (!state.sfx || !ensure()) return;
    const t = ctx.currentTime;
    const playing = (state.playing[name] || []).filter((x) => x > t - 0.15);
    if (playing.length >= Config.sounds.maxSame) return; // spam never becomes noise
    playing.push(t); state.playing[name] = playing;
    if (name === 'bank') {
      const now = performance.now() / 1000;
      state.bankStreak = now - (state.bankAt || -99) < Config.sounds.bankStreakReset ? (state.bankStreak || 0) + 1 : 0;
      state.bankAt = now; n = state.bankStreak;
    }
    if (name === 'coin') {
      const now = performance.now() / 1000;
      state.streak = now - state.streakAt < Config.sounds.streakReset ? state.streak + 1 : 0;
      state.streakAt = now; n = state.streak;
    }
    sounds[name]?.(t, n);
  }
  let musicTimer = null;
  function startMusic() {
    // a gentle, cheerful loop per place: the hub and Meadow are bright and twinkly, the Forest is
    // lower and woodier (in Roblox these are two music ids crossfaded by the zone)
    const tunes = {
      meadow: [523, 659, 784, 659, 587, 698, 880, 698, 523, 659, 784, 1046, 988, 784, 659, 587],
      forest: [392, 494, 587, 494, 440, 523, 659, 523, 392, 494, 587, 784, 698, 587, 494, 440],
    };
    let i = 0;
    musicTimer = setInterval(() => {
      if (!state.music || !ctx) return;
      const t = ctx.currentTime, notes = tunes[state.zone === 2 ? 'forest' : 'meadow'];
      tone(notes[i % notes.length] / 2, t, 0.5, 'triangle', 0.35, musicBus);
      if (i % 4 === 0) tone(notes[i % notes.length] / 4, t, 0.9, 'sine', 0.4, musicBus);
      i++;
    }, 300);
  }
  return {
    unlock: ensure, play,
    setMusic(on) { state.music = on; }, setSfx(on) { state.sfx = on; }, setZone(z) { state.zone = z; },
    get music() { return state.music; }, get sfx() { return state.sfx; },
  };
}
