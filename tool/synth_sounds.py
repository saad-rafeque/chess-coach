"""Synthesizes clean, modern board sounds (preview copies, not yet in the app).

move: crisp soft tock. capture: heavier double tap. check: soft bell.
victory: gentle ascending chime. defeat: calm descending two notes.
"""
import math
import os
import struct
import subprocess
import wave

RATE = 44100
FADE = int(0.005 * RATE)  # 5 ms fade-out to avoid clicks


def sine(freq, dur, amp=1.0, attack=0.004, decay=5.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t / dur)
        v = math.sin(2 * math.pi * freq * t) + 0.22 * math.sin(2 * math.pi * freq * 2 * t)
        out.append(amp * env * v)
    return out


def knock(freq=700.0, dur=0.09, amp=1.0):
    """A wooden tap: tiny noise transient + a fast-decaying body tone."""
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        noise = 0.0
        if t < 0.004:
            noise = (((i * 2654435761) % 1000) / 1000 * 2 - 1) * (1 - t / 0.004) * 0.45
        body = math.sin(2 * math.pi * freq * t) * math.exp(-48.0 * t)
        out.append(amp * (body + noise))
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*tracks):
    n = max((len(t) for t in tracks), default=0)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def master(samples, peak=0.7):
    m = max((abs(s) for s in samples), default=0.0) or 1.0
    k = peak / m
    return [s * k for s in samples]


def write_wav(path, samples):
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            frames += struct.pack('<h', int(max(-1.0, min(1.0, s)) * 32767))
        w.writeframes(bytes(frames))


def to_mp3(wav, mp3):
    subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-q:a', '4', mp3],
        check=True,
    )


# --- move: crisp soft tock ------------------------------------------------
move = master(mix(knock(700, 0.09, 1.0), knock(1050, 0.05, 0.30)))

# --- capture: heavier double tap -----------------------------------------
capture = master(mix(
    knock(620, 0.10, 1.0),
    silence(0.055) + knock(540, 0.09, 0.80),
))

# --- check: soft bell ding (E6) -------------------------------------------
check = master(mix(
    sine(1318.5, 0.50, amp=0.60, attack=0.002, decay=7.0),
    sine(2637.0, 0.35, amp=0.14, attack=0.002, decay=8.0),
))

# --- victory: gentle ascending chime C5-E5-G5 ------------------------------
victory = master(mix(
    sine(523.25, 0.50, amp=0.50, decay=4.0),
    silence(0.16) + sine(659.25, 0.50, amp=0.50, decay=4.0),
    silence(0.32) + sine(783.99, 0.65, amp=0.55, decay=3.5),
))

# --- defeat: calm descending A3-F3 ------------------------------------------
defeat = master(mix(
    sine(220.00, 0.60, amp=0.55, attack=0.010, decay=3.0),
    silence(0.30) + sine(174.61, 0.80, amp=0.60, attack=0.010, decay=2.6),
))

out_dir = os.path.expanduser('~/Downloads/chess-coach-builds/sounds-preview')
os.makedirs(out_dir, exist_ok=True)
for name, samples in [('move', move), ('capture', capture), ('check', check),
                      ('victory', victory), ('defeat', defeat)]:
    wav = f'/tmp/{name}.wav'
    write_wav(wav, samples)
    to_mp3(wav, os.path.join(out_dir, f'{name}.mp3'))
    print(f'{name}: {len(samples) / RATE:.2f}s -> {out_dir}/{name}.mp3')
