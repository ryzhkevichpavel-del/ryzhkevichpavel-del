#!/usr/bin/env python3
from pathlib import Path
import math,os,random,struct,wave,zlib
R=Path(__file__).resolve().parents[1];T=R/'assets/textures';A=R/'assets/audio';S=int(os.getenv('TB_TEXTURE_SIZE','512'))
def C(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
def png(p,w,h,n,b):
 raw=b''.join(b'\0'+bytes(b[y*w*n:(y+1)*w*n]) for y in range(h));p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b'\x89PNG\r\n\x1a\n'+C(b'IHDR',struct.pack('>IIBBBBB',w,h,8,{1:0,3:2,4:6}[n],0,0,0))+C(b'IDAT',zlib.compress(raw,9))+C(b'IEND',b''))
def H(x,y,s):
 n=(x*520197045)^(y*1597334677)^(s*73244475);n=(n^(n>>16))*73244475;n=(n^(n>>16))*73244475;return ((n^(n>>16))&0xffffffff)/4294967295
def V(u,v,c,s):
 x=u*c;y=v*c;i=int(x)%c;j=int(y)%c;fx=(x-int(x));fy=(y-int(y));fx*=fx*(3-2*fx);fy*=fy*(3-2*fy)
 a=H(i,j,s);b=H((i+1)%c,j,s);d=H(i,(j+1)%c,s);e=H((i+1)%c,(j+1)%c,s);return (a+(b-a)*fx)*(1-fy)+(d+(e-d)*fx)*fy
def F(u,v,s):return sum(V(u,v,3<<i,s+i*17)*(0.55*.48**i) for i in range(4))/sum(0.55*.48**i for i in range(4))
def q(x):return max(0,min(255,int(x+.5)))
def tex():
 T.mkdir(parents=True,exist_ok=True);N=S*S;sh=[0.0]*N;wh=[0.0]*N
 for y in range(S):
  v=y/S
  for x in range(S):
   u=x/S;sh[y*S+x]=F(u,v,17)*.48+V(u,v,64,73)*.22+math.sin((u*.94+v*.34)*math.tau*22+F(u,v,91)*2.3)*.055+H(x,y,133)*.035
   wh[y*S+x]=math.sin((u*.83+v*.55)*math.tau*6)+math.sin((-u*.41+v*.92)*math.tau*12+.7)*.48+math.sin((u*.17+v*1.08)*math.tau*25+1.8)*.2+(F(u,v,309)-.5)*.5
 out={k:bytearray(N*n) for k,n in [('sand',3),('wet',3),('rough',1),('sn',3),('wn',3),('foam',1),('rock',3),('wood',3)]}
 for y in range(S):
  for x in range(S):
   i=y*S+x;o=i*3;u=x/S;v=y/S;g=H(x,y,701)-.5;w=.78+sh[i]*.3+g*.055
   out['sand'][o:o+3]=bytes((q(218*w),q(176*w),q(112*w)));out['wet'][o:o+3]=bytes((q(112*w),q(91*w),q(65*w)));out['rough'][i]=q(186+(1-sh[i])*55+g*18)
   for key,h,k in [('sn',sh,7),('wn',wh,1.7)]:
    dx=h[y*S+(x+1)%S]-h[y*S+(x-1)%S];dy=h[((y+1)%S)*S+x]-h[((y-1)%S)*S+x];nx=-dx*k;ny=-dy*k;z=1;d=(nx*nx+ny*ny+1)**-.5;out[key][o:o+3]=bytes((q((nx*d*.5+.5)*255),q((ny*d*.5+.5)*255),q(d*255)))
   cell=abs(math.sin((u+F(u,v,441)*.1)*math.tau*14)*math.cos((v+F(u,v,443)*.1)*math.tau*17));thr=abs(math.sin((u*1.31+v*.78)*math.tau*24+F(u,v,449)*5));out['foam'][i]=q(max(0,min(1,(cell-.54)*2.8+(thr-.82)*1.6))*255)
   m=F(u,v,911);rc=.5+m*.42+(.1 if H(x,y,917)>.985 else 0);out['rock'][o:o+3]=bytes((q(132*rc),q(128*rc),q(120*rc)));wc=.72+math.sin((u*1.05+math.sin(v*math.tau*2)*.04)*math.tau*22+F(u,v,1013)*2.2)*.13+(F(u,v,1021)-.5)*.22;out['wood'][o:o+3]=bytes((q(135*wc),q(85*wc),q(48*wc)))
 for f,k,n in [('sand_albedo.png','sand',3),('wet_sand_albedo.png','wet',3),('sand_roughness.png','rough',1),('sand_normal.png','sn',3),('water_normal.png','wn',3),('foam.png','foam',1),('rock_albedo.png','rock',3),('wood_albedo.png','wood',3)]:png(T/f,S,S,n,out[k])
def icon():
 s=256;b=bytearray(s*s*4)
 for y in range(s):
  for x in range(s):
   t=y/(s-1);a=(26,72,96) if t<.58 else ((54,150,163) if t<.72 else (210,154,79));o=(y*s+x)*4;b[o:o+4]=bytes((*a,255))
 def r(x0,y0,x1,y1,c):
  for y in range(y0,y1):
   for x in range(x0,x1):b[(y*s+x)*4:(y*s+x)*4+4]=bytes(c)
 sand=(238,183,99,255);r(76,116,180,216,sand);r(52,94,100,205,sand);r(156,94,204,205,sand);r(124,55,128,116,(92,58,36,255));r(128,58,176,82,(202,66,50,255));r(108,166,148,216,(112,69,39,255));png(R/'assets/icon.png',s,s,4,b)
def wav(p,ch,rate,frames):
 p.parent.mkdir(parents=True,exist_ok=True)
 with wave.open(str(p),'wb') as f:f.setparams((ch,2,rate,0,'NONE',''));f.writeframes(b''.join(struct.pack('<h',max(-32767,min(32767,int(v*32767)))) for fr in frames for v in fr))
def audio():
 A.mkdir(parents=True,exist_ok=True);r=22050;g=random.Random(12345);ls=rs=0;o=[]
 for i in range(r*8):
  t=i/r;e=.55+.3*math.sin(math.tau*t/8)+.12*math.sin(math.tau*3*t/8+.7);ls=ls*.965+g.uniform(-1,1)*.035;rs=rs*.965+g.uniform(-1,1)*.035;u=math.sin(math.tau*.23*t)*.12+math.sin(math.tau*.41*t+1.2)*.07;o.append(((ls*.48+u)*e,(rs*.48+u)*e))
 wav(A/'ocean_loop.wav',2,r,o)
 for name,d,fn in [('sand.wav',.48,lambda t:g.uniform(-1,1)*math.exp(-t*8)*.22),('build.wav',.62,lambda t:math.sin(math.tau*(74-28*t)*t)*.28*math.exp(-t*5.3)),('rock.wav',.72,lambda t:(math.sin(math.tau*(96-55*t)*t)*.48+math.sin(math.tau*47*t)*.22)*math.exp(-t*7)),('wave.wav',2,lambda t:(g.uniform(-1,1)*.3+math.sin(math.tau*.75*t)*.18)*math.sin(math.pi*min(1,t/.6))*math.exp(-max(0,t-.65)*1.2))]:wav(A/name,1,r,[(fn(i/r),) for i in range(int(r*d))])
if __name__=='__main__':tex();icon();audio();print('Generated assets in',R)
