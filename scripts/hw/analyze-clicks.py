#!/usr/bin/env python3
"""Compares a microphone and a system audio recording made while clicks played through the speakers.

    afconvert -f WAVE -d LEI16@48000 "<name> (mic).m4a" build/mic.wav
    afconvert -f WAVE -d LEI16@48000 "<name> (system).m4a" build/sys.wav
    python3 scripts/hw/analyze-clicks.py build/mic.wav build/sys.wav

Prints the track lengths, the spacing of the clicks in the system track (1.0 s when nothing was
lost; a shorter one marks lost audio), the microphone peak per 0.5 s, and for each system click the
microphone's peak and onset offset in ms (strong clicks should agree within about 10 ms).
"""
import struct, sys
def load(p):
    b=open(p,'rb').read(); i=12; ch=1; r=48000
    while i<len(b):
        cid=b[i:i+4]; sz=struct.unpack('<I',b[i+4:i+8])[0]
        if cid==b'fmt ': ch,r=struct.unpack('<HI',b[i+10:i+16])
        if cid==b'data': d=b[i+8:i+8+sz]; break
        i+=8+sz+(sz&1)
    n=len(d)//(2*ch); a=struct.unpack('<%dh'%(n*ch), d[:n*ch*2]); return [a[k*ch]/32768 for k in range(n)], r
mic,r=load(sys.argv[1]); sysa,_=load(sys.argv[2])
print("lengths mic=%.3fs sys=%.3fs diff=%d frames"%(len(mic)/r,len(sysa)/r,len(mic)-len(sysa)))
def onsets(x,thr):
    out=[];i=0
    while i<len(x):
        if abs(x[i])>thr: out.append(i); i+=int(0.3*r)
        else: i+=1
    return out
so=onsets(sysa,0.15)
print("system clicks:",len(so)," spacings:",sorted(set(round((b-a)/r,3) for a,b in zip(so,so[1:]))))
# mic activity per 0.5 s
blk=r//2
print("mic peak per 0.5s:"," ".join("%.2f"%max(abs(v) for v in mic[i:i+blk]) for i in range(0,len(mic)-blk,blk)))
# for each system click, find mic peak within +-60ms window and its offset
pk=max(abs(v) for v in mic) or 1
res=[]
for o in so:
    w=mic[max(0,o-int(.06*r)):o+int(.06*r)]
    if not w: continue
    m=max(range(len(w)),key=lambda k:abs(w[k]))
    # onset: first sample in window above 50% of window max
    amp=abs(w[m]); first=next(k for k in range(len(w)) if abs(w[k])>=0.5*amp)
    res.append((round(o/r,2), round(amp,3), round((first-int(.06*r))/r*1000,1)))
print("click t, mic amp, mic onset offset ms:"); print(res)
