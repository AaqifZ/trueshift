"""Generate data-driven diagrams (why.html, seasons.html) into ../src/.
Run: ~/.claude/venv/bin/python docs/img/gen/make.py  (needs: astral). Then docs/img/src/render.sh."""
import math, datetime, zoneinfo
from pathlib import Path
from astral import LocationInfo
from astral.sun import sun

SRC = Path(__file__).resolve().parent.parent / "src"
TZ = zoneinfo.ZoneInfo("Australia/Sydney")
LOC = LocationInfo("Sydney", "AU", "Australia/Sydney", -33.87, 151.21)

def k2rgb(k):
    t = k / 100
    r = 255 if t <= 66 else 329.698727446 * (t - 60) ** -0.1332047592
    g = 99.4708025861 * math.log(t) - 161.1195681661 if t <= 66 else 288.1221695283 * (t - 60) ** -0.0755148492
    b = 255 if t >= 66 else (0 if t <= 19 else 138.5177312231 * math.log(t - 10) - 305.0447927307)
    c = lambda v: max(0, min(255, int(v)))
    return f"#{c(r):02x}{c(g):02x}{c(b):02x}"

def hours(dt): return dt.hour + dt.minute / 60

def suntimes(d):
    s = sun(LOC.observer, date=d, tzinfo=TZ)
    return hours(s["sunrise"]), hours(s["sunset"])

def kelvin(h, rise, set_):
    lerp = lambda a, b, f: a + (b - a) * max(0, min(1, f))
    if h < rise: return 1000
    if h < rise + .5: return lerp(1000, 5500, (h - rise) / .5)
    if h < set_ - 3: return 5500
    if h < set_: return lerp(5500, 2700, (h - (set_ - 3)) / 3)
    if h < set_ + 2: return lerp(2700, 1000, (h - set_) / 2)
    return 1000

def hhmm(h): return f"{int(h):02d}:{int(round((h % 1) * 60)):02d}"

HEAD = '<!doctype html><html data-size="1600,{h}"><head><meta charset="utf-8"><link rel="stylesheet" href="base.css"></head><body>\n<svg width="1600" height="{h}" viewBox="0 0 1600 {h}">\n'

# ---------- why.html: sky vs normal screen vs trueshift, one real Sydney day ----------
D = datetime.date(2026, 10, 4)
rise, set_ = suntimes(D)
X0, X1 = 330, 1520
px = lambda h: X0 + (X1 - X0) * h / 24
stops = lambda f: "".join(f'<stop offset="{i/96:.4f}" stop-color="{f(i/4)}"/>' for i in range(97))

def sky(h):
    # stylised sky: night navy, warm at sunrise/sunset, pale blue by day
    if h < rise - 1 or h > set_ + 1.2: return "#0f172a"
    if h < rise: return "#7c2d12"
    if h < rise + 1: return "#fb923c"
    if h < set_ - 1.5: return "#bfdbfe"
    if h < set_: return "#fdba74"
    if h < set_ + .6: return "#ea580c"
    return "#4c1d95"

s = HEAD.format(h=760)
s += '<defs>'
s += f'<linearGradient id="sky">{stops(sky)}</linearGradient>'
s += f'<linearGradient id="rs">{stops(lambda h: k2rgb(kelvin(h, rise, set_)))}</linearGradient>'
s += '</defs>\n'
s += '<text x="60" y="78" class="t">My screen should tell my body the same time the sky does</text>\n'
s += f'<text x="60" y="116" class="st">One real day in Sydney, {D.strftime("%-d %B %Y")}. Sunrise {hhmm(rise)}, sunset {hhmm(set_)}.</text>\n'
rows = [("The sky", "url(#sky)", 190), ("A normal screen", k2rgb(6500), 340), ("With trueshift", "url(#rs)", 490)]
for label, fill, y in rows:
    s += f'<text x="60" y="{y+62}" class="h">{label}</text>\n'
    s += f'<rect x="{X0}" y="{y}" width="{X1-X0}" height="100" rx="14" fill="{fill}" stroke="#cbd5e1" stroke-width="2"/>\n'
# 10pm marker
x22 = px(22)
s += f'<path d="M{x22},170 V610" stroke="#0f172a" stroke-width="3" stroke-dasharray="6 6"/>\n'
s += f'<rect x="{x22-46}" y="146" width="92" height="30" rx="15" fill="#0f172a"/><text x="{x22}" y="167" text-anchor="middle" font-size="16" font-weight="700" class="wh">10 pm</text>\n'
s += f'<text x="{x22-14}" y="402" text-anchor="end" font-size="20" font-weight="700" fill="#0f172a">says "noon"</text>\n'
s += f'<text x="{x22-14}" y="552" text-anchor="end" font-size="20" font-weight="700" fill="#fff">says "firelight"</text>\n'
for h in (0, 6, 12, 18, 24):
    s += f'<text x="{px(h)}" y="630" text-anchor="middle" class="m">{h:02d}:00</text>\n'
s += '<rect x="60" y="666" width="1460" height="64" rx="12" fill="#fff7ed" stroke="#ff9900" stroke-width="2"/>\n'
s += '<text x="88" y="706" font-size="21" fill="#9a3412"><tspan font-weight="700">The principle:</tspan> light is information for my body. A tool should pass on the truth about the time, not hide it.</text>\n'
s += '</svg></body></html>\n'
(SRC / "why.html").write_text(s)

# ---------- seasons.html: Sydney curve, December vs June ----------
DEC, JUN = datetime.date(2026, 12, 21), datetime.date(2026, 6, 21)
(dr, ds), (jr, js) = suntimes(DEC), suntimes(JUN)
Y = lambda k: 620 - (k - 1000) * (380 / 4500)
X0, X1 = 160, 1500
px = lambda h: X0 + (X1 - X0) * h / 24
def path(r, st):
    pts = [(px(i / 12), Y(kelvin(i / 12, r, st))) for i in range(24 * 12 + 1)]
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
s = HEAD.format(h=800)
s += '<text x="60" y="78" class="t">Same city, different sun</text>\n'
s += '<text x="60" y="116" class="st">Trueshift follows the real sunrise and sunset where I am, so the red arrives at a different time each season.</text>\n'
s += f'<path d="M{X0},200 V620 H{X1}" fill="none" stroke="#94a3b8" stroke-width="2"/>\n'
for k in (1000, 2700, 5500):
    s += f'<text x="{X0-14}" y="{Y(k)+6}" text-anchor="end" class="m">{k}K</text>\n'
for h in (0, 6, 12, 18, 24):
    s += f'<text x="{px(h)}" y="650" text-anchor="middle" class="m">{h:02d}:00</text>\n'
s += f'<path d="{path(dr, ds)}" fill="none" stroke="#ff9900" stroke-width="6" stroke-linejoin="round"/>\n'
s += f'<path d="{path(jr, js)}" fill="none" stroke="#2563eb" stroke-width="6" stroke-linejoin="round"/>\n'
# dusk-start markers
for (r, st, col, anchor, dx) in ((dr, ds, "#ff9900", "start", 14), (jr, js, "#2563eb", "end", -14)):
    x = px(st - 3)
    s += f'<circle cx="{x}" cy="{Y(5500)}" r="8" fill="{col}"/>\n'
    s += f'<text x="{x+dx}" y="{Y(5500)-16}" text-anchor="{anchor}" font-size="18" font-weight="700" fill="{col}">warming starts {hhmm(st-3)}</text>\n'
    x2 = px(st + 2)
    s += f'<circle cx="{x2}" cy="{Y(1000)}" r="8" fill="{col}"/>\n'
s += f'<text x="{px(js+2)-50}" y="{Y(1000)-40}" text-anchor="end" font-size="18" font-weight="700" fill="#2563eb">deep red {hhmm(js+2)}</text>\n'
s += f'<text x="{px(ds+2)+20}" y="{Y(1000)-18}" text-anchor="start" font-size="18" font-weight="700" fill="#ff9900">deep red {hhmm(ds+2)}</text>\n'
# legend
s += f'<rect x="610" y="330" width="420" height="96" rx="12" fill="#fff" stroke="#cbd5e1" stroke-width="2"/>\n'
s += f'<rect x="634" y="356" width="28" height="8" rx="4" fill="#ff9900"/><text x="676" y="366" class="b">21 December: sun up {hhmm(dr)} to {hhmm(ds)}</text>\n'
s += f'<rect x="634" y="394" width="28" height="8" rx="4" fill="#2563eb"/><text x="676" y="404" class="b">21 June: sun up {hhmm(jr)} to {hhmm(js)}</text>\n'
gap = (ds - js)
s += '<rect x="160" y="690" width="1340" height="74" rx="12" fill="#f1f5f9"/>\n'
s += f'<text x="186" y="736" class="b"><tspan font-weight="700">{int(gap)} h {int(round(gap%1*60))} min apart.</tspan> A fixed "red at 9 pm" timer is wrong half the year. My only setting is where I live.</text>\n'
s += '</svg></body></html>\n'
(SRC / "seasons.html").write_text(s)
print("sunrise/sunset", D, hhmm(rise), hhmm(set_), "| Dec", hhmm(dr), hhmm(ds), "| Jun", hhmm(jr), hhmm(js))
