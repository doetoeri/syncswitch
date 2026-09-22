#!/usr/bin/env python3
# TapeReader icon generator.
# Uses only original geometric artwork: no bundled third-party images, logos, fonts, or icon packs.
import math, os, struct, zlib, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources"

def clamp(v,a=0.0,b=1.0):
    return a if v<a else b if v>b else v

def mix(a,b,t):
    return a + (b-a)*t

def blend(dst, src, a):
    a=clamp(a)
    ia=1.0-a
    return (int(dst[0]*ia+src[0]*a), int(dst[1]*ia+src[1]*a), int(dst[2]*ia+src[2]*a), 255)

def rounded_inside(x,y,x0,y0,x1,y1,r):
    cx = min(max(x, x0+r), x1-r)
    cy = min(max(y, y0+r), y1-r)
    dx=x-cx; dy=y-cy
    return dx*dx+dy*dy <= r*r

def render(size):
    scale=3
    n=size*scale
    pix=[(0,0,0,255)]*(n*n)

    # Deep slate-blue field with a soft radial highlight.
    for y in range(n):
        ty=y/max(1,n-1)
        base=(int(mix(66,18,ty)), int(mix(91,39,ty)), int(mix(121,67,ty)))
        for x in range(n):
            dx=(x-n*.34)/(n*.78); dy=(y-n*.12)/(n*.9)
            glow=max(0.0,1.0-math.sqrt(dx*dx+dy*dy))*0.15
            c=(min(255,int(base[0]+255*glow)),min(255,int(base[1]+255*glow)),min(255,int(base[2]+255*glow)),255)
            pix[y*n+x]=c

    def fill_round(x0,y0,x1,y1,r,color,alpha=1.0):
        ix0=max(0,int(x0)); iy0=max(0,int(y0)); ix1=min(n,int(x1)+1); iy1=min(n,int(y1)+1)
        for yy in range(iy0,iy1):
            for xx in range(ix0,ix1):
                if rounded_inside(xx+.5,yy+.5,x0,y0,x1,y1,r):
                    i=yy*n+xx
                    pix[i]=blend(pix[i],color,alpha)

    # Paper shadow, spread over multiple layers.
    px0=n*.235; py0=n*.14; px1=n*.765; py1=n*.845; pr=n*.035
    for spread,alpha in [(13,.06),(9,.08),(5,.12)]:
        fill_round(px0+spread*.35,py0+spread,px1+spread*.35,py1+spread,pr+spread*.12,(0,0,0),alpha)

    # Warm paper.
    fill_round(px0,py0,px1,py1,pr,(245,242,227),1.0)
    # Paper highlight.
    fill_round(px0+n*.008,py0+n*.008,px1-n*.008,py0+n*.055,pr*.75,(255,255,250),.48)

    # Folded upper-right page corner.
    fold=n*.105
    for yy in range(int(py0), int(py0+fold)):
        for xx in range(int(px1-fold), int(px1)):
            if (xx-(px1-fold)) + (yy-py0) >= fold:
                i=yy*n+xx
                pix[i]=blend(pix[i],(216,219,212),.95)
    # Fold shadow line.
    for k in range(max(1,int(n*.006))):
        yy0=int(py0+fold-k)
        for xx in range(int(px1-fold),int(px1)):
            yy=int(py0+fold-(xx-(px1-fold))-k)
            if 0<=yy<n:
                i=yy*n+xx
                pix[i]=blend(pix[i],(120,125,128),.25)

    # Subtle document lines, kept broad enough for 50px icon.
    line_left=int(n*.31); line_right=int(n*.69)
    for frac,width in [(0.31,.27),(0.37,.33),(0.43,.22),(0.67,.31),(0.73,.25)]:
        yy=int(n*frac); h=max(1,int(n*.012))
        rr=line_left+int(n*width)
        for y in range(max(0,yy-h//2), min(n,yy+h//2+1)):
            for x in range(line_left,min(n,rr)):
                i=y*n+x
                pix[i]=blend(pix[i],(111,119,124),.38)

    # Masking tape: warm yellow, slightly translucent and irregular at the edges.
    tx0=int(n*.105); tx1=int(n*.895); mid=n*.535; half=n*.075
    for x in range(tx0,tx1):
        t=(x-tx0)/max(1,tx1-tx0-1)
        edge=math.sin(t*23.0)*n*.0025 + math.sin(t*61.0)*n*.0012
        top=int(mid-half+edge); bottom=int(mid+half-edge*.7)
        for y in range(max(0,top),min(n,bottom)):
            v=(y-top)/max(1,bottom-top-1)
            col=(int(mix(250,229,v)),int(mix(224,190,v)),int(mix(111,74,v)))
            alpha=.94 if px0 <= x <= px1 else .89
            i=y*n+x
            pix[i]=blend(pix[i],col,alpha)
        # fibrous vertical grain
        if x % max(2,int(n*.012)) == 0:
            for y in range(max(0,top+2),min(n,bottom-2)):
                if (y+x) % 7 == 0:
                    i=y*n+x
                    pix[i]=blend(pix[i],(255,247,188),.12)

    # Tape top highlight and lower contact shadow.
    for x in range(tx0,tx1):
        top=int(mid-half + math.sin(((x-tx0)/max(1,tx1-tx0))*23)*n*.0025)
        if 0<=top<n:
            for k in range(max(1,int(n*.006))):
                y=top+k
                if 0<=y<n:
                    i=y*n+x
                    pix[i]=blend(pix[i],(255,252,215),.23*(1-k/max(1,int(n*.006))))
        bottom=int(mid+half)
        y=bottom+max(1,int(n*.008))
        if 0<=y<n:
            i=y*n+x
            pix[i]=blend(pix[i],(0,0,0),.08)

    # A lifted right edge cue: small bright folded tip.
    tipx=int(n*.84); tipy=int(mid-half)
    for y in range(tipy, min(n,tipy+int(n*.06))):
        for x in range(tipx,min(n,tipx+int(n*.06))):
            if (x-tipx) > (y-tipy)*.55:
                i=y*n+x
                pix[i]=blend(pix[i],(255,242,174),.72)

    # Downsample by box average.
    out=bytearray(size*size*4)
    for y in range(size):
        for x in range(size):
            sr=sg=sb=0
            for yy in range(y*scale,(y+1)*scale):
                base=yy*n+x*scale
                for xx in range(scale):
                    r,g,b,a=pix[base+xx]
                    sr+=r; sg+=g; sb+=b
            samples=scale*scale
            j=(y*size+x)*4
            out[j]=sr//samples; out[j+1]=sg//samples; out[j+2]=sb//samples; out[j+3]=255
    return out

def write_png(path,w,h,rgba):
    raw=bytearray()
    stride=w*4
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y*stride:(y+1)*stride])
    def chunk(kind,data):
        return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
    png=b"\x89PNG\r\n\x1a\n"
    png+=chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,6,0,0,0))
    png+=chunk(b"IDAT",zlib.compress(bytes(raw),9))
    png+=chunk(b"IEND",b"")
    with open(path,"wb") as f: f.write(png)

os.makedirs(OUT,exist_ok=True)
targets=[
    ("Icon.png",72),
    ("Icon@2x.png",144),
    ("Icon-72.png",72),
    ("Icon-72@2x.png",144),
    ("Icon-Small-50.png",50),
    ("Icon-Small-50@2x.png",100),
]
for name,size in targets:
    write_png(os.path.join(OUT,name),size,size,render(size))
print("generated",", ".join(name for name,_ in targets))
