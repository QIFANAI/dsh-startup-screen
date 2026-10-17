"""Normalise the BGM bed to the plugin's asset reference level.

"In Cyberpunk" arrives as a streaming master: peak 0.0 dBFS and active-RMS
-9.2 dBFS, i.e. 13.4 dB louder than the five voice lines (-22.6 dBFS).
Fed through the same player gain it would bury every line, so the file is
attenuated to a fixed reference (-18 dBFS active-RMS) and the *player* then
applies the far smaller, user-tunable bgmVolume on top.
"""

import os
import sys
import wave
import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(_HERE, "_bgm", "bgm-source.wav")
DST = os.path.join(_HERE, "_bgm", "bgm-normalized.wav")
TARGET_RMS_DBFS = float(sys.argv[1]) if len(sys.argv) > 1 else -18.0


def active_rms_dbfs(x):
    active = x[np.abs(x) > 10 ** (-45 / 20)]
    if active.size == 0:
        return -np.inf
    return 20 * np.log10(np.sqrt(np.mean(active ** 2)))


w = wave.open(SRC, "rb")
n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
raw = w.readframes(n)
w.close()
if sw != 2:
    raise SystemExit("expected 16-bit PCM, got %d bytes/sample" % sw)

data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
before_peak = 20 * np.log10(max(np.max(np.abs(data)), 1e-12))
before_rms = active_rms_dbfs(data)

gain_db = TARGET_RMS_DBFS - before_rms
out = data * (10 ** (gain_db / 20))
peak = np.max(np.abs(out))
if peak >= 1.0:
    raise SystemExit("would clip: peak %.3f after %+.2f dB" % (peak, gain_db))

pcm = np.clip(np.rint(out * 32767.0), -32768, 32767).astype("<i2").tobytes()
with wave.open(DST, "wb") as fh:
    fh.setnchannels(ch)
    fh.setsampwidth(2)
    fh.setframerate(sr)
    fh.writeframes(pcm)

after = np.frombuffer(pcm, dtype="<i2").astype(np.float64) / 32768.0
print("source      : %d Hz, %d ch, %.2f s" % (sr, ch, n / sr))
print("before      : peak %.1f dBFS, active-RMS %.1f dB" % (before_peak, before_rms))
print("gain        : %+.1f dB -> target active-RMS %.1f dB" % (gain_db, TARGET_RMS_DBFS))
print("after       : peak %.1f dBFS, active-RMS %.1f dB (headroom %.1f dB)"
      % (20 * np.log10(max(np.max(np.abs(after)), 1e-12)), active_rms_dbfs(after),
         -20 * np.log10(max(np.max(np.abs(after)), 1e-12))))
print("written     : %s (%.1f MB)" % (DST, os.path.getsize(DST) / 1048576))
