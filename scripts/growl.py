# A short voiced growl with irregular vocal pulses, two resonances and an airy tail.
from math import cos, sin, exp, pi
import random, wave, struct
from pathlib import Path
import sys
sr=32000
rng=random.Random(724)
p=0;lp=0;a1=b1=a2=b2=0;out=[]
for i in range(int(sr*.68)):
 t=i/sr;u=t/.68
 p+=(139-48*u+5*sin(2*pi*24*t)+3*sin(2*pi*5*t))/sr
 n=rng.uniform(-1,1)
 lp+=.19*(n-lp)
 source=(max(0,1-7*(p%1))-.07)*(1+.32*sin(2*pi*31*t))+.11*lp
 r1=exp(-pi*115/sr);r2=exp(-pi*190/sr)
 v1=source+2*r1*cos(2*pi*(580-260*u)/sr)*a1-r1*r1*b1
 v2=source+2*r2*cos(2*pi*(1270-430*u)/sr)*a2-r2*r2*b2
 b1,a1=a1,v1;b2,a2=a2,v2
 env=min(1,t/.065)*min(1,(.68-t)/.19)*(.83+.17*sin(pi*u))
 out.append(env*(v1+.7*v2))
scale=12000/max(abs(x) for x in out)
path=Path(sys.argv[1])
with wave.open(str(path),'wb') as w:
 w.setparams((1,2,sr,0,'NONE','not compressed'));w.writeframes(b''.join(struct.pack('<h',round(x*scale)) for x in out))
