#!/usr/bin/env python3
"""Writes a stereo 48 kHz WAV with one sharp click per second, for alignment and gap checks.

    python3 scripts/hw/make-clicks.py build/clicks.wav 150   # 150 seconds
    afplay build/clicks.wav &
"""
import math, struct, sys, wave

path, seconds = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 60
rate = 48000
second = bytearray()
for t in range(rate):
    v = 0.9 * math.exp(-t / 40.0) * (1 if (t // 6) % 2 == 0 else -1) if t < 400 else 0.0
    s = int(v * 32767)
    second += struct.pack('<hh', s, s)
w = wave.open(path, 'wb')
w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
w.writeframes(bytes(second) * seconds)
w.close()
