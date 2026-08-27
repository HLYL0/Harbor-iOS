import json
import urllib.request
import html


def get(url):
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "HarborIOS/0.2",
            "Accept": "application/json, text/plain, */*",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response)


def esc(value):
    return html.escape(value or "")


movies = get("https://v3-cinemeta.strem.io/catalog/movie/top.json")["metas"][:9]
series = get("https://v3-cinemeta.strem.io/catalog/series/top.json")["metas"][:9]
hero = movies[0]
matrix = get("https://v3-cinemeta.strem.io/meta/movie/tt0133093.json")["meta"]

hero_bg = hero.get("background") or hero.get("poster") or ""
hero_name = esc(hero.get("name") or "")
hero_rating = hero.get("imdbRating") or ""
hero_year = (hero.get("releaseInfo") or "")[:4]
genres = " • ".join((matrix.get("genres") or [])[:3])
rating = matrix.get("imdbRating") or ""
release = matrix.get("releaseInfo") or ""
description = esc((matrix.get("description") or "")[:240])


def poster_card(meta):
    poster = meta.get("poster") or ""
    name = esc(meta.get("name") or "")
    rating = meta.get("imdbRating") or ""
    return (
        '<div class="poster"><div class="ph"><img src="%s" loading="lazy" '
        'onerror="this.style.visibility=\'hidden\'"><div class="pr">&#9733; %s</div></div>'
        "<span>%s</span></div>" % (poster, rating, name)
    )


movies_html = "".join(poster_card(m) for m in movies)
series_html = "".join(poster_card(m) for m in series)

TEMPLATE = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root { --canvas:#15161A; --surface:#1D1E24; --elevated:#25262E; --raised:#2F303A; --ink:#F5F5F7; --muted:#B8B8C2; --subtle:#8A8A96; --edge:rgba(255,255,255,.16); --edgeSoft:rgba(255,255,255,.08); --accent:#E9C55E; --accentSoft:rgba(233,197,94,.18); --success:#4CC38A; --danger:#E5484D; }
* { margin:0; padding:0; box-sizing:border-box; -webkit-font-smoothing:antialiased; }
body { background:radial-gradient(1200px 600px at 20% -10%,rgba(233,197,94,.07),transparent 60%),#0C0D10; font-family:-apple-system,'SF Pro Display',system-ui,'Segoe UI',sans-serif; color:var(--ink); display:flex; justify-content:center; padding:18px 10px; }
.phone { width:393px; height:852px; background:var(--canvas); border:1px solid rgba(255,255,255,.16); border-radius:50px; position:relative; overflow:hidden; box-shadow:0 30px 90px rgba(0,0,0,.65), inset 0 0 0 3px #0A0B0E; }
.statusbar { position:absolute; top:0; left:0; right:0; height:47px; display:flex; align-items:center; justify-content:space-between; padding:0 30px; font-size:14px; font-weight:600; z-index:20; pointer-events:none; }
.island { position:absolute; top:11px; left:50%; transform:translateX(-50%); width:118px; height:32px; background:#000; border-radius:20px; z-index:21; pointer-events:none; }
.screen { position:absolute; inset:0; overflow:hidden; display:none; flex-direction:column; }
.screen.active { display:flex; animation:fadeUp .35s ease; }
@keyframes fadeUp { from { opacity:0; transform:translateY(12px); } to { opacity:1; transform:none; } }
.tabbar { position:absolute; left:14px; right:14px; bottom:14px; height:58px; display:flex; align-items:center; justify-content:space-around; background:rgba(29,30,36,.88); backdrop-filter:blur(20px); -webkit-backdrop-filter:blur(20px); border:1px solid var(--edgeSoft); border-radius:20px; z-index:9; }
.tab { display:flex; flex-direction:column; align-items:center; gap:2px; font-size:10px; color:var(--subtle); cursor:pointer; background:none; border:none; padding:8px 26px; border-radius:14px; transition:color .2s; }
.tab .ic { font-size:19px; }
.tab.on { color:var(--accent); }
.title { font-size:31px; font-weight:800; padding:56px 20px 4px; letter-spacing:-.3px; }
.search { margin:10px 20px 16px; background:rgba(37,38,46,.7); backdrop-filter:blur(14px); -webkit-backdrop-filter:blur(14px); border:1px solid var(--edgeSoft); border-radius:14px; padding:11px 14px; color:var(--subtle); font-size:15px; display:flex; gap:9px; align-items:center; }
.chips { display:flex; gap:8px; padding:0 20px 18px; }
.chip { background:var(--elevated); border:1px solid var(--edgeSoft); color:var(--muted); font-size:12.5px; font-weight:600; padding:7px 14px; border-radius:20px; cursor:pointer; transition:all .18s; }
.chip.on { background:var(--accentSoft); border-color:var(--accent); color:var(--accent); }
.hero { position:relative; margin:0 20px 24px; height:352px; border-radius:22px; overflow:hidden; border:1px solid var(--edgeSoft); cursor:pointer; box-shadow:0 18px 44px rgba(0,0,0,.45); }
.hero img { width:100%; height:100%; object-fit:cover; transition:transform .5s ease; }
.hero:hover img { transform:scale(1.04); }
.hero .grad { position:absolute; inset:0; background:linear-gradient(180deg,rgba(21,22,26,.1) 20%,rgba(21,22,26,.62) 62%,#15161A 96%); }
.hero .badge { position:absolute; top:14px; left:14px; background:var(--accent); color:#1A1503; font-size:10px; font-weight:900; letter-spacing:.6px; padding:5px 10px; border-radius:8px; box-shadow:0 4px 16px rgba(233,197,94,.35); }
.hero .bottom { position:absolute; left:16px; right:16px; bottom:16px; }
.hero .name { font-size:26px; font-weight:800; letter-spacing:-.3px; text-shadow:0 2px 18px rgba(0,0,0,.7); }
.hero .meta { display:flex; gap:8px; align-items:center; margin-top:8px; font-size:12px; font-weight:700; color:var(--muted); }
.hero .meta .star { color:var(--accent); }
.rail { margin-bottom:24px; }
.rail h2 { font-size:19px; font-weight:800; padding:0 20px 12px; letter-spacing:-.2px; }
.rail h2 small { color:var(--subtle); font-weight:600; font-size:12px; margin-left:8px; }
.scroll { display:flex; gap:13px; overflow-x:auto; padding:2px 20px 8px; scrollbar-width:none; }
.scroll::-webkit-scrollbar { display:none; }
.poster { width:108px; flex:0 0 108px; }
.ph { position:relative; border-radius:14px; overflow:hidden; border:1px solid var(--edgeSoft); transition:transform .2s ease, box-shadow .2s ease; }
.poster:hover .ph { transform:translateY(-4px); box-shadow:0 12px 26px rgba(0,0,0,.5); }
.poster img { width:108px; height:160px; object-fit:cover; background:var(--elevated); display:block; }
.pr { position:absolute; left:6px; bottom:6px; background:rgba(0,0,0,.66); backdrop-filter:blur(6px); font-size:9.5px; font-weight:800; color:var(--accent); padding:3px 7px; border-radius:7px; }
.poster span { display:block; margin-top:7px; font-size:11.5px; color:var(--muted); line-height:1.3; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.backdrop { position:relative; height:272px; flex:0 0 auto; }
.backdrop img { width:100%; height:100%; object-fit:cover; }
.backdrop .grad { position:absolute; inset:0; background:linear-gradient(180deg,rgba(21,22,26,.28) 0%,rgba(21,22,26,.6) 58%,#15161A 100%); }
.back { position:absolute; top:58px; left:16px; background:rgba(29,30,36,.72); backdrop-filter:blur(10px); border:1px solid var(--edgeSoft); color:var(--ink); width:36px; height:36px; border-radius:50%; font-size:17px; cursor:pointer; z-index:3; }
.detailbody { padding:0 20px; overflow-y:auto; margin-top:-56px; position:relative; z-index:2; }
.dname { font-size:28px; font-weight:800; letter-spacing:-.4px; }
.meta { display:flex; gap:9px; align-items:center; font-size:12.5px; font-weight:700; color:var(--muted); margin-top:9px; flex-wrap:wrap; }
.meta .chipx { background:var(--elevated); border:1px solid var(--edgeSoft); padding:5px 10px; border-radius:8px; }
.meta .star { color:var(--accent); background:var(--accentSoft); border-color:transparent; }
.desc { margin-top:14px; font-size:13.5px; color:var(--muted); line-height:1.6; }
.cta { margin-top:18px; background:var(--accent); color:#1A1503; font-weight:800; font-size:16px; border-radius:15px; padding:15px; text-align:center; cursor:pointer; border:none; width:100%; box-shadow:0 10px 30px rgba(233,197,94,.28); transition:transform .15s; }
.cta:active { transform:scale(.97); }
.src { margin-top:24px; }
.src h3 { font-size:19px; font-weight:800; margin-bottom:12px; }
.row { display:flex; gap:13px; align-items:center; background:var(--surface); border:1px solid var(--edgeSoft); border-radius:16px; padding:14px; margin-bottom:10px; cursor:pointer; transition:border-color .2s, transform .15s; }
.row:hover { border-color:var(--edge); transform:translateX(3px); }
.row .ico { font-size:19px; color:var(--accent); }
.row .g { font-size:19px; color:var(--success); }
.row .o { font-size:19px; color:#FB923C; }
.row .info { flex:1; min-width:0; }
.row .t1 { font-size:13.5px; font-weight:700; }
.row .t2 { font-size:11px; color:var(--subtle); margin-top:3px; }
.badge { font-size:9.5px; font-weight:900; letter-spacing:.5px; padding:4px 9px; border-radius:7px; }
.b-direct { background:var(--accentSoft); color:var(--accent); }
.b-debrid { background:rgba(76,195,138,.16); color:var(--success); }
.b-resolver { background:rgba(251,146,60,.14); color:#FB923C; }
.player { background:#000; }
video { position:absolute; inset:0; width:100%; height:100%; object-fit:contain; }
.ptop { position:absolute; top:0; left:0; right:0; padding:58px 18px 26px; background:linear-gradient(180deg,rgba(0,0,0,.72),transparent); display:flex; align-items:center; gap:14px; z-index:4; transition:opacity .25s; }
.ptop .bk { font-size:19px; cursor:pointer; color:#fff; }
.ptop .pt { font-size:14px; font-weight:700; text-shadow:0 1px 8px rgba(0,0,0,.8); }
.pbottom { position:absolute; left:0; right:0; bottom:0; padding:26px 18px 40px; background:linear-gradient(0deg,rgba(0,0,0,.8),transparent); z-index:4; transition:opacity .25s; }
.progwrap { display:flex; align-items:center; gap:10px; }
.ptime { font-size:10.5px; color:#D7D7DD; font-variant-numeric:tabular-nums; min-width:38px; text-align:center; }
.bar { flex:1; height:20px; display:flex; align-items:center; cursor:pointer; position:relative; }
.track { position:relative; width:100%; height:4px; background:rgba(255,255,255,.22); border-radius:3px; }
.buff { position:absolute; left:0; top:0; bottom:0; background:rgba(255,255,255,.35); border-radius:3px; }
.fill { position:absolute; left:0; top:0; bottom:0; background:var(--accent); border-radius:3px; }
.knob { position:absolute; top:50%; width:13px; height:13px; border-radius:50%; background:var(--accent); transform:translate(-50%,-50%); box-shadow:0 2px 8px rgba(233,197,94,.6); }
.pcontrols { display:flex; align-items:center; justify-content:space-between; margin-top:8px; padding:0 14px; }
.ctls { display:flex; align-items:center; gap:26px; }
.cbtn { background:none; border:none; color:#fff; font-size:17px; cursor:pointer; padding:4px; }
.playbig { width:54px; height:54px; border-radius:50%; background:rgba(255,255,255,.14); backdrop-filter:blur(8px); display:flex; align-items:center; justify-content:center; font-size:20px; cursor:pointer; border:1px solid rgba(255,255,255,.2); }
.speed { background:rgba(255,255,255,.14); border:1px solid rgba(255,255,255,.2); color:#fff; font-size:12px; font-weight:800; padding:7px 12px; border-radius:10px; cursor:pointer; }
.hidden { opacity:0; pointer-events:none; }
.set { padding:56px 20px 96px; overflow-y:auto; }
.set h1 { font-size:31px; font-weight:800; letter-spacing:-.3px; margin-bottom:18px; }
.sec { background:var(--surface); border:1px solid var(--edgeSoft); border-radius:18px; padding:16px; margin-bottom:14px; }
.sec h4 { font-size:11px; color:var(--subtle); text-transform:uppercase; letter-spacing:.7px; margin-bottom:10px; font-weight:800; }
.kv { display:flex; align-items:center; gap:10px; font-size:14px; padding:7px 0; color:var(--ink); }
.kv .ok { color:var(--success); }
.kv .avatar { width:30px; height:30px; border-radius:9px; background:var(--elevated); display:flex; align-items:center; justify-content:center; font-size:15px; }
.btn { display:block; width:100%; text-align:left; background:none; border:none; color:var(--accent); font-size:14px; font-weight:600; padding:9px 0; cursor:pointer; }
.btn.danger { color:var(--danger); }
.note { font-size:11.5px; color:var(--subtle); line-height:1.5; margin-top:8px; }
.field { background:var(--elevated); border:1px solid var(--edgeSoft); border-radius:11px; padding:11px 13px; font-size:13.5px; color:var(--subtle); margin-bottom:9px; }
</style></head>
<body>
<div class="phone">
  <div class="island"></div>
  <div class="statusbar"><span>9:41</span><span style="display:flex;gap:6px;align-items:center;">&#9656;&#65039; &#9657; &#9660; &#128267;</span></div>

  <div class="screen active" id="home">
    <div class="title">Harbor</div>
    <div class="search">&#128269; &nbsp;Movies and series</div>
    <div class="chips"><span class="chip on">All</span><span class="chip">Movies</span><span class="chip">Series</span></div>
    <div style="flex:1;overflow-y:auto;padding-bottom:92px;">
      <div class="hero" onclick="show('detail')"><img src="HERO_BG"><div class="grad"></div><div class="badge">&#9654; &nbsp;TOP MOVIE</div><div class="bottom"><div class="name">HERO_NAME</div><div class="meta"><span class="star">&#9733; HERO_RATING</span><span>HERO_YEAR</span><span>Action · Thriller</span></div></div></div>
      <div class="rail"><h2>Top Movies<small>8 titles</small></h2><div class="scroll">MOVIES_HTML</div></div>
      <div class="rail"><h2>Top Series<small>8 titles</small></h2><div class="scroll">SERIES_HTML</div></div>
    </div>
  </div>

  <div class="screen" id="detail">
    <div class="backdrop"><img src="HERO_BG"><div class="grad"></div><button class="back" onclick="show('home')">&#8249;</button></div>
    <div class="detailbody">
      <div class="dname">The Matrix</div>
      <div class="meta"><span class="chipx star">&#9733; RATING</span><span class="chipx">RELEASE</span><span class="chipx">GENRES</span></div>
      <div class="desc">DESCRIPTION…</div>
      <button class="cta" onclick="reveal()">&#9654; &nbsp;Find Streams</button>
      <div class="src" id="sources" style="display:none;">
        <h3>Sources</h3>
        <div class="row" onclick="playIt(this)"><span class="g">&#9889;</span><div class="info"><div class="t1">4K &nbsp;HEVC &nbsp;· &nbsp;Torrentio RD+</div><div class="t2">Torrentio</div></div><span class="badge b-debrid">DEBRID</span></div>
        <div class="row" onclick="playIt(this)"><span class="g">&#9889;</span><div class="info"><div class="t1">1080p &nbsp;· &nbsp;Torrentio RD</div><div class="t2">Torrentio</div></div><span class="badge b-debrid">DEBRID</span></div>
        <div class="row" onclick="playIt(this)"><span class="g">&#9889;</span><div class="info"><div class="t1">2160p &nbsp;· &nbsp;Comet RD</div><div class="t2">Comet</div></div><span class="badge b-debrid">DEBRID</span></div>
        <div class="row" onclick="playIt(this)"><span class="ico">&#9654;</span><div class="info"><div class="t1">1080p &nbsp;· &nbsp;Streaming</div><div class="t2">WatchHub</div></div><span class="badge b-direct">DIRECT</span></div>
        <div class="row"><span class="o">&#128279;</span><div class="info"><div class="t1">720p &nbsp;· &nbsp;External</div><div class="t2">MediaFusion</div></div><span class="badge b-resolver">RESOLVER</span></div>
      </div>
    </div>
  </div>

  <div class="screen player" id="player">
    <video id="v" src="https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4" playsinline></video>
    <div class="ptop" id="ptop"><span class="bk" onclick="show('detail')">&#8249;</span><span class="pt">The Matrix · 4K HEVC · Torrentio</span></div>
    <div class="pbottom" id="pbottom">
      <div class="progwrap"><span class="ptime" id="cur">0:00</span><div class="bar" id="bar"><div class="track"><div class="buff" id="buff"></div><div class="fill" id="fill"></div><div class="knob" id="knob" style="left:0%"></div></div></div><span class="ptime" id="dur">0:00</span></div>
      <div class="pcontrols"><div class="ctls"><button class="cbtn" id="rw">&#9198; 10</button><div class="playbig" id="pp">&#9654;</div><button class="cbtn" id="ff">10 &#9197;</button></div><button class="speed" id="spd">1&#215;</button></div>
    </div>
  </div>

  <div class="screen" id="settings">
    <div class="set">
      <h1>Settings</h1>
      <div class="sec"><h4>Stremio Account</h4>
        <div class="kv"><span class="ok">&#10004;</span> husho1 · synced</div>
        <button class="btn">&#8635; &nbsp;Sync Addons</button>
        <button class="btn danger">Sign Out</button>
      </div>
      <div class="sec"><h4>Debrid · Real-Debrid</h4>
        <div class="kv"><span class="ok">&#128737;</span> API key saved in Keychain</div>
        <button class="btn danger">Remove Key</button>
        <div class="note">Torrent sources resolve through Real-Debrid so they can play on iOS. The key never leaves your device.</div>
      </div>
      <div class="sec"><h4>Install Addon</h4>
        <div class="field">https://…/manifest.json</div>
        <button class="btn">Install Manifest</button>
      </div>
      <div class="sec"><h4>Installed Addons · 16</h4>
        <div class="kv"><span class="avatar">&#129520;</span>Torrentio</div>
        <div class="kv"><span class="avatar">&#9732;&#65039;</span>Comet</div>
        <div class="kv"><span class="avatar">&#128172;</span>OpenSubtitles</div>
      </div>
      <div class="sec"><div class="note">Playback: libmpv (MoltenVK) · Debrid: Real-Debrid · Catalog: Cinemeta.</div></div>
    </div>
  </div>

  <div class="tabbar">
    <button class="tab on" onclick="tab('home')"><span class="ic">&#127968;</span>Home</button>
    <button class="tab" onclick="tab('settings')"><span class="ic">&#9881;&#65039;</span>Settings</button>
  </div>
</div>
<script>
function show(id) { document.querySelectorAll('.screen').forEach(function(s){s.classList.remove('active');}); document.getElementById(id).classList.add('active'); if(id==='player'){ v.play(); } }
function tab(id) { show(id); var tabs=document.querySelectorAll('.tab'); tabs.forEach(function(t){t.classList.remove('on');}); tabs[(id==='home'?0:1)].classList.add('on'); }
function reveal() { document.getElementById('sources').style.display='block'; }
var v=document.getElementById('v'), fill=document.getElementById('fill'), buff=document.getElementById('buff'), knob=document.getElementById('knob'), cur=document.getElementById('cur'), dur=document.getElementById('dur'), pp=document.getElementById('pp'), spd=document.getElementById('spd');
function fmt(t){ if(!isFinite(t)||t<0)t=0; var m=Math.floor(t/60), s=Math.floor(t%60); return m+':'+(s<10?'0':'')+s; }
v.addEventListener('loadedmetadata',function(){ dur.textContent=fmt(v.duration); });
v.addEventListener('timeupdate',function(){ if(v.duration){ var p=v.currentTime/v.duration*100; fill.style.width=p+'%'; knob.style.left=p+'%'; cur.textContent=fmt(v.currentTime); } if(v.buffered.length){ buff.style.width=(v.buffered.end(v.buffered.length-1)/v.duration*100)+'%'; } });
v.addEventListener('play',function(){ pp.textContent='❚❚'; });
v.addEventListener('pause',function(){ pp.textContent='▶'; });
pp.onclick=function(){ v.paused?v.play():v.pause(); };
document.getElementById('rw').onclick=function(){ v.currentTime=Math.max(0,v.currentTime-10); };
document.getElementById('ff').onclick=function(){ v.currentTime=Math.min(v.duration,v.currentTime+10); };
var speeds=[1,1.25,1.5,2,0.5], si=0;
spd.onclick=function(){ si=(si+1)%speeds.length; v.playbackRate=speeds[si]; spd.textContent=speeds[si]+'×'; };
var bar=document.getElementById('bar'), seek=false;
function seekTo(ev){ var r=bar.getBoundingClientRect(); var p=Math.min(1,Math.max(0,(ev.clientX-r.left)/r.width)); v.currentTime=p*v.duration; }
bar.addEventListener('mousedown',function(ev){ seek=true; seekTo(ev); });
window.addEventListener('mousemove',function(ev){ if(seek) seekTo(ev); });
window.addEventListener('mouseup',function(){ seek=false; });
var hideTimer;
function peek(){ var p=document.getElementById('ptop'), b=document.getElementById('pbottom'); p.classList.remove('hidden'); b.classList.remove('hidden'); clearTimeout(hideTimer); hideTimer=setTimeout(function(){ if(!v.paused){ p.classList.add('hidden'); b.classList.add('hidden'); } },3200); }
document.getElementById('player').addEventListener('click',peek);
peek();
document.querySelectorAll('.chip').forEach(function(c){ c.onclick=function(){ document.querySelectorAll('.chip').forEach(function(x){x.classList.remove('on');}); c.classList.add('on'); }; });
function playIt(row){ var t=row.querySelector('.t1').textContent; document.getElementById('pt').textContent='The Matrix · '+t.replace(/\u00a0/g,' '); show('player'); }
</script>
</body></html>"""

html_page = TEMPLATE
html_page = html_page.replace("HERO_BG", hero_bg)
html_page = html_page.replace("HERO_NAME", hero_name)
html_page = html_page.replace("HERO_RATING", hero_rating)
html_page = html_page.replace("HERO_YEAR", hero_year)
html_page = html_page.replace("MOVIES_HTML", movies_html)
html_page = html_page.replace("SERIES_HTML", series_html)
html_page = html_page.replace("RELEASE", release)
html_page = html_page.replace("RATING", rating)
html_page = html_page.replace("GENRES", genres)
html_page = html_page.replace("DESCRIPTION", description)

out_path = r"C:/Users/Admin/Desktop/Harbor-iOS-ui-preview.html"
with open(out_path, "w", encoding="utf-8") as handle:
    handle.write(html_page)
print("UI_PREVIEW_V2_READY", len(html_page), "chars")
