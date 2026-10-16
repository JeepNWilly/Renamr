#!/usr/bin/env python3
"""Build a Plex rename plan (plan.csv) from a list of Windows paths using TMDB.
Usage: python3 plan.py paths.txt --movies-root "Z:\\...\\Movies" --series-root "Z:\\...\\Series" [-o plan.csv]
Requires env TMDB_API_KEY (v3 key). Never writes the key anywhere."""
import argparse, csv, json, ntpath, os, re, sys, time, unicodedata, urllib.parse, urllib.request, urllib.error
from difflib import SequenceMatcher

VIDEO = {'.mkv', '.mp4', '.avi', '.m4v', '.mov', '.wmv', '.mpg', '.mpeg', '.ts', '.m2ts', '.webm', '.flv', '.divx'}
SIDECAR = {'.srt', '.sub', '.idx', '.ass', '.ssa', '.vtt', '.smi', '.nfo'}
TAGS = set('''480p 576p 720p 1080p 1080i 2160p 4k uhd hdr hdr10 dv sdr x264 x265 h264 h265 hevc avc xvid divx 10bit 8bit
bluray blu-ray brrip bdrip webrip web-dl webdl web hdtv pdtv dvdrip dvdscr dvd scr screener cam ts tc hdcam r5 hdrip remux
aac aac2 ac3 dts dd5 ddp5 atmos truehd mp3 extended ext hc anime dual audio ita eng dlmux anniversary unrated remastered directors cut dc theatrical imax proper repack
internal limited multi subbed dubbed complete criterion edition uncut rarbg yts yify eztv ettv amzn nf hulu dsnp hmax'''.split())
ILLEGAL = re.compile(r'[<>"/\\|?*\x00-\x1f]')
EP_RE = re.compile(r'(?i)(?<![a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?:[ ._-]*-?e(\d{1,3}))?(?![a-z0-9])|(?<![a-z0-9])(\d{1,2})x(\d{2,3})(?![a-z0-9])')
ABS_RE = re.compile(r'(?i)^(.*?)\s-\s(\d{1,3})(?!\d)|^(.*?)[ ._-]part[ ._](\d{1,2})(?!\d)')
SKIP_DIRS = re.compile(r'(?i)\\(Plex Versions|ROMS)\\')
YEAR_RE = re.compile(r'(?<!\d)(19[2-9]\d|20[0-4]\d)(?!\d)')

class TMDB:
    def __init__(self, key, cache_path):
        self.key, self.cache_path, self.last = key, cache_path, 0.0
        self.cache = json.load(open(cache_path, encoding='utf-8')) if os.path.exists(cache_path) else {}
        self.dirty = 0
    def get(self, path, **params):
        params = {k: v for k, v in params.items() if v not in (None, '')}
        ck = path + '?' + urllib.parse.urlencode(sorted(params.items()))
        if ck in self.cache: return self.cache[ck]
        url = 'https://api.themoviedb.org/3' + path + '?' + urllib.parse.urlencode({**params, 'api_key': self.key})
        for attempt in range(6):
            wait = 0.03 - (time.time() - self.last)   # ~30 req/s, under TMDB's ~40/s
            if wait > 0: time.sleep(wait)
            self.last = time.time()
            try:
                with urllib.request.urlopen(url, timeout=20) as r: data = json.load(r)
                break
            except urllib.error.HTTPError as e:
                if e.code == 404: data = None; break
                if e.code == 429 or e.code >= 500:
                    time.sleep(float(e.headers.get('Retry-After') or 2 ** attempt)); continue
                raise RuntimeError(f'TMDB HTTP {e.code} on {path}') from None
            except urllib.error.URLError:
                time.sleep(2 ** attempt)
        else: raise RuntimeError(f'TMDB unreachable for {path}')
        self.cache[ck] = data; self.dirty += 1
        if self.dirty >= 50: self.save()
        return data
    def save(self):
        tmp = self.cache_path + '.tmp'
        json.dump(self.cache, open(tmp, 'w', encoding='utf-8'))
        os.replace(tmp, self.cache_path); self.dirty = 0

def norm(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower().replace('&', 'and')
    return re.sub(r'[^a-z0-9]+', ' ', s).strip()
def sim(a, b): return SequenceMatcher(None, norm(a), norm(b)).ratio()
def safe(name):
    name = name.replace(': ', ' ' if ' - ' in name else ' - ').replace(':', '-')
    name = ILLEGAL.sub('', name)
    return re.sub(r'\s+', ' ', name).strip().rstrip('. ')

def clean_tokens(text):
    """Split on separators, return tokens up to first release tag."""
    text = re.sub(r'\[[^\]]*\]|\{[^}]*\}', ' ', text)
    text = re.sub(r'(?i)\b\d+(st|nd|rd|th)[ ._]anniversary\b', ' anniversary', text)
    text = re.sub(r'-(?=(19|20)\d\d(\D|$))', ' ', text)
    text = re.sub(r'[._]+', ' ', text)
    text = re.sub(r'\s-\s?[A-Za-z0-9]+$', ' ', text)  # trailing -GROUP
    toks = text.replace('(', ' ').replace(')', ' ').split()
    out = []
    for t in toks:
        tl = t.lower().strip('-')
        base = tl.split('-')[0]
        if tl in TAGS or base in TAGS or re.fullmatch(r'\d{3,4}p', tl): break
        out.append(t)
    return out

def parse_movie(stem):
    stem = re.sub(r'^\d{1,2}[ ._-]+(?=[A-Za-z])', '', stem)   # leading collection index "01 Evangelion ..."
    toks = clean_tokens(stem)
    year, title = None, toks
    for i in range(len(toks) - 1, 0, -1):  # last year token not at position 0 (e.g. "2012", "1917")
        if YEAR_RE.fullmatch(toks[i]): year, title = int(toks[i]), toks[:i]; break
    return ' '.join(title).strip(' -'), year

def parse_show(text):
    toks = clean_tokens(text)
    year = None
    if len(toks) > 1 and YEAR_RE.fullmatch(toks[-1]): year = int(toks[-1]); toks = toks[:-1]
    return ' '.join(toks).strip(' -'), year

def match_movie(db, title, year):
    best = None
    for y in ([year, None] if year else [None]):
        res = (db.get('/search/movie', query=title, primary_release_year=y, include_adult='false') or {}).get('results', [])
        for r in res[:8]:
            ry = int(r['release_date'][:4]) if r.get('release_date') else None
            s = max(sim(title, r.get('title', '')), sim(title, r.get('original_title', '')))
            yok = year is None or (ry is not None and abs(ry - year) <= 1)
            score = s + (0.15 if year and ry == year else 0) - (0 if yok else 0.4) + min(r.get('popularity', 0), 50) / 1000
            if ry and (best is None or score > best[0]): best = (score, r, s, ry, yok)
        if best and best[2] >= 0.85 and best[4]: break
    if year and (not best or best[2] < 0.6):  # e.g. "Star Wars Episode IV A New Hope" -> TMDB "Star Wars"
        res = (db.get('/search/movie', query=title, primary_release_year=year) or {}).get('results', [])
        for r in res[:3]:
            if r.get('release_date', '')[:4] == str(year) and norm(r['title']) and norm(title).startswith(norm(r['title'])):
                return r['id'], safe(r['title']), year, 'low', f'partial title match "{r["title"]}" ({year})'
    if not best: return None
    score, r, s, ry, yok = best
    high = s >= 0.9 and year is not None and (ry == year or (s >= 0.97 and abs(ry - year) <= 1))
    if s < 0.6: return None
    return r['id'], safe(r['title']), ry, 'high' if high else 'low', f'matched "{r["title"]}" ({ry}) sim={s:.2f}' + ('' if year else '; no year in filename')

def match_show(db, name, year):
    best = None
    for y in ([year, None] if year else [None]):
        res = (db.get('/search/tv', query=name, first_air_date_year=y) or {}).get('results', [])
        for r in res[:8]:
            ry = int(r['first_air_date'][:4]) if r.get('first_air_date') else None
            s = max(sim(name, r.get('name', '')), sim(name, r.get('original_name', '')))
            score = s + (0.15 if year and ry == year else 0) + min(r.get('popularity', 0), 50) / 500
            if ry and (best is None or score > best[0]): best = (score, r, s, ry)
        if best: break
    if not best or best[2] < 0.6: return None
    _, r, s, ry = best
    return r['id'], safe(r['name']), ry, s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('paths'); ap.add_argument('--movies-root', required=True); ap.add_argument('--series-root', required=True)
    ap.add_argument('-o', '--output', default='plan.csv'); ap.add_argument('--cache', default='tmdb_cache.json')
    a = ap.parse_args()
    key = os.environ.get('TMDB_API_KEY') or sys.exit('TMDB_API_KEY not set')
    db = TMDB(key, a.cache)
    mroot, sroot = a.movies_root.rstrip('\\'), a.series_root.rstrip('\\')
    paths = [l.strip().lstrip('\ufeff') for l in open(a.paths, encoding='utf-8-sig') if l.strip()]
    under = lambda p, root: p.lower().startswith(root.lower() + '\\')
    excluded = [p for p in paths if SKIP_DIRS.search(p)]
    paths_ok = [p for p in paths if not SKIP_DIRS.search(p)]
    videos = [p for p in paths_ok if ntpath.splitext(p)[1].lower() in VIDEO]
    sidecars = [p for p in paths_ok if ntpath.splitext(p)[1].lower() in SIDECAR]
    print(f'{len(paths)} paths: {len(videos)} videos, {len(sidecars)} sidecars, {len(excluded)} excluded (Plex Versions/ROMS), '
          f'{len(paths_ok)-len(videos)-len(sidecars)} other files ignored')
    rows, shows, seasons = [], {}, {}
    for p in videos:
        d, fn = ntpath.split(p); stem, ext = ntpath.splitext(fn); ext = ext.lower()
        row = dict(old_path=p, new_path='', media_type='', tmdb_id='', confidence='', note='')
        try:
            m = EP_RE.search(stem)
            absm = ABS_RE.search(stem.replace('_', ' ')) if under(p, sroot) and not m else None
            if under(p, sroot) and not m and not absm:
                row['media_type'] = 'episode'
                row['note'] = 'unmatched: no SxxEyy in name (stray file in Series root?)'; rows.append(row); continue
            if under(p, sroot) or (under(p, mroot) and m):
                row['media_type'] = 'episode'
                extra = []
                if under(p, mroot): extra.append('episode found under Movies root; planned into Series root')
                if m:
                    s, e1, e2 = (int(m[1]), int(m[2]), m[3]) if m[1] else (int(m[4]), int(m[5]), None)
                    mstart, mend = m.start(), m.end()
                else:
                    s, e1, e2 = 1, int(absm[2] or absm[4]), None
                    extra.append('no SxxEyy; assumed s01 from absolute/part number - verify')
                    mstart, mend = len(absm[1] if absm[1] is not None else absm[3]), absm.end()
                root = sroot if under(p, sroot) else mroot
                rel = p[len(root) + 1:].split('\\')
                cand = parse_show(stem[:mstart])
                if not cand[0] and len(rel) > 1: cand = parse_show(rel[0])
                key2 = (norm(cand[0]), cand[1])
                if key2 not in shows:
                    shows[key2] = match_show(db, *cand)
                    if not shows[key2] and len(rel) > 1:  # retry with top folder name
                        shows[key2] = match_show(db, *parse_show(rel[0]))
                sh = shows[key2]
                if not sh: row['note'] = f'unmatched: no TMDB show for "{cand[0]}"'; rows.append(row); continue
                tid, sname, sy, ssim = sh
                if (tid, s) not in seasons: seasons[(tid, s)] = db.get(f'/tv/{tid}/season/{s}')
                eps = {ep['episode_number']: ep.get('name', '') for ep in (seasons[(tid, s)] or {}).get('episodes', [])}
                ftitle = ' '.join(clean_tokens(stem[mend:]))
                notes = [f'show "{sname}" sim={ssim:.2f}'] + extra
                if (e1 == 0 or e1 not in eps) and ftitle and s != 0:  # e.g. S09E00 Christmas special -> Season 00 by title
                    if (tid, 0) not in seasons: seasons[(tid, 0)] = db.get(f'/tv/{tid}/season/0')
                    sp = {ep['episode_number']: ep.get('name', '') for ep in (seasons[(tid, 0)] or {}).get('episodes', [])}
                    nf = norm(ftitle)
                    cands = [(max(sim(ftitle, t), 1.0 if len(norm(t)) > 6 and norm(t) in nf else 0), n) for n, t in sp.items()]
                    if cands and max(cands)[0] >= 0.75:
                        bn = max(cands)[1]; notes.append(f'moved s{s:02d}e{e1:02d} -> special s00e{bn:02d} by title'); s, e1, eps = 0, bn, sp
                if ftitle and eps and not e2 and e1 in eps and norm(ftitle) != norm(sname) and len(ftitle.split()) >= 2:
                    bn, bs = max(((n, sim(ftitle, t)) for n, t in eps.items()), key=lambda x: x[1])
                    if bs >= 0.8 and bn != e1 and sim(ftitle, eps.get(e1, '')) < 0.6:
                        notes.append(f'renumbered e{e1}->e{bn} by title "{eps[bn]}"'); e1 = bn
                titlemismatch = bool(ftitle and eps.get(e1) and sim(ftitle, eps[e1]) < 0.5 and not ftitle.lower().startswith(norm(eps[e1])[:8]))
                if titlemismatch: notes.append(f'filename title "{ftitle[:40]}" differs from TMDB (number kept)')
                if s == 0: notes.append('special (Season 00) - verify numbering')
                show = f'{sname} ({sy})'
                code = f's{s:02d}e{e1:02d}' + (f'-e{int(e2):02d}' if e2 else '')
                title = eps.get(e1)
                if e2 and eps.get(int(e2)): title = f'{title} + {eps[int(e2)]}' if title else eps[int(e2)]
                if not title: notes.append('episode not found on TMDB')
                if title and re.fullmatch(r'Episode \d+', title): title = None
                fname = safe(f'{show} - {code}' + (f' - {title}' if title else '')) + ext
                row.update(new_path=ntpath.join(sroot, safe(show), f'Season {s:02d}', fname), tmdb_id=tid,
                           confidence='high' if ssim >= 0.9 and title and s and not extra else 'low', note='; '.join(notes))
            elif under(p, mroot):
                row['media_type'] = 'movie'
                title, year = parse_movie(stem)
                mm = match_movie(db, title, year) if title else None
                if not mm: row['note'] = f'unmatched: no TMDB movie for "{title}" ({year})'; rows.append(row); continue
                tid, t, y, conf, note = mm
                base = safe(f'{t} ({y})')
                row.update(new_path=ntpath.join(mroot, base, base + ext), tmdb_id=tid, confidence=conf, note=note)
            else:
                row['note'] = 'unmatched: path not under movies or series root'
        except RuntimeError as ex:
            row['note'] = f'error: {ex}'
        rows.append(row)
    db.save()
    # collisions / already-correct
    taken, existing = {}, {p.lower() for p in paths}
    rows.sort(key=lambda r: (r['confidence'] != 'high', r['old_path'].lower()))  # high-confidence wins a contested target
    for r in rows:
        if not r['new_path']: continue
        if r['new_path'] == r['old_path']:
            r['new_path'] = ''; r['note'] = 'already correctly named; skipped'; continue
        k = r['new_path'].lower()
        if k in taken:
            r['note'] = f'DUPLICATE: same target as {taken[k]}; ' + r['note']; r['new_path'] = ''; r['confidence'] = 'low'; continue
        if k in existing and k != r['old_path'].lower():
            r['note'] = 'COLLISION: target already exists in library; ' + r['note']; r['new_path'] = ''; r['confidence'] = 'low'; continue
        taken[k] = r['old_path']
    by_folder = {}
    for r in rows:
        if r['new_path'] and r['media_type'] == 'movie': by_folder.setdefault(ntpath.dirname(r['new_path']).lower(), []).append(r)
    for g in by_folder.values():
        if len(g) > 1:
            for r in g: r['note'] = f'MULTIPLE VERSIONS ({len(g)} files) of same movie; ' + r['note']
    # sidecars follow their video: same folder with matching stem, or Subs\<videostem>\N_Lang.srt, or Subs\lang.srt
    LANG = {'english': 'en', 'eng': 'en', 'spanish': 'es', 'spa': 'es', 'french': 'fr', 'fre': 'fr', 'fra': 'fr', 'german': 'de',
            'ger': 'de', 'deu': 'de', 'italian': 'it', 'ita': 'it', 'portuguese': 'pt', 'por': 'pt', 'brazilian': 'pt-BR', 'dutch': 'nl',
            'dut': 'nl', 'russian': 'ru', 'rus': 'ru', 'japanese': 'ja', 'jpn': 'ja', 'korean': 'ko', 'kor': 'ko', 'chinese': 'zh',
            'chi': 'zh', 'zho': 'zh', 'arabic': 'ar', 'ara': 'ar', 'hebrew': 'he', 'heb': 'he', 'polish': 'pl', 'pol': 'pl',
            'swedish': 'sv', 'swe': 'sv', 'norwegian': 'no', 'nor': 'no', 'nob': 'no', 'danish': 'da', 'dan': 'da', 'finnish': 'fi',
            'fin': 'fi', 'greek': 'el', 'gre': 'el', 'ell': 'el', 'turkish': 'tr', 'tur': 'tr', 'czech': 'cs', 'cze': 'cs', 'ces': 'cs',
            'hungarian': 'hu', 'hun': 'hu', 'romanian': 'ro', 'rum': 'ro', 'ron': 'ro', 'thai': 'th', 'tha': 'th', 'vietnamese': 'vi',
            'vie': 'vi', 'indonesian': 'id', 'ind': 'id', 'malay': 'ms', 'may': 'ms', 'msa': 'ms', 'hindi': 'hi', 'hin': 'hi',
            'ukrainian': 'uk', 'ukr': 'uk', 'croatian': 'hr', 'hrv': 'hr', 'bulgarian': 'bg', 'bul': 'bg', 'slovak': 'sk', 'slo': 'sk',
            'slovenian': 'sl', 'slv': 'sl', 'catalan': 'ca', 'cat': 'ca', 'basque': 'eu', 'baq': 'eu', 'galician': 'gl', 'glg': 'gl',
            'icelandic': 'is', 'ice': 'is', 'estonian': 'et', 'est': 'et', 'latvian': 'lv', 'lav': 'lv', 'lithuanian': 'lt',
            'lit': 'lt', 'filipino': 'fil', 'fil': 'fil', 'tamil': 'ta', 'tam': 'ta', 'telugu': 'te', 'tel': 'te', 'persian': 'fa',
            'per': 'fa', 'serbian': 'sr', 'srp': 'sr', 'kannada': 'kn', 'kan': 'kn', 'malayalam': 'ml', 'mal': 'ml', 'bengali': 'bn', 'bokmal': 'nb', 'nob': 'nb'}
    def lang_suffix(name):
        words = re.findall(r'[a-z]+', name.lower())
        code = next((LANG[w] for w in words if w in LANG), None)
        if not code: return None
        flags = [f for f in ('forced', 'sdh') if f in words] + (['sdh'] if 'hi' in words and 'sdh' not in words else [])
        return '.' + '.'.join([code] + flags)
    vids = {r['old_path'].lower(): r for r in rows if r['media_type'] in ('movie', 'episode')}
    vid_by_dir = {}
    for r in vids.values(): vid_by_dir.setdefault(ntpath.dirname(r['old_path']).lower(), []).append(r)
    stem_of = lambda r: ntpath.splitext(ntpath.basename(r['old_path']))[0]
    for p in sorted(sidecars, key=lambda x: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', x.lower())]):
        d, fn = ntpath.split(p); parts = d.split('\\')
        row = dict(old_path=p, new_path='', media_type='sidecar', tmdb_id='', confidence='', note='')
        v, suffix = None, None
        cands = [r for r in vid_by_dir.get(d.lower(), []) if fn.lower().startswith(stem_of(r).lower())]
        if cands:
            v = max(cands, key=lambda r: len(stem_of(r))); suffix = fn[len(stem_of(v)):].lower()
        elif 'subs' in [x.lower() for x in parts[-2:]]:
            i = len(parts) - 1 - [x.lower() for x in parts[::-1]].index('subs')
            parent = '\\'.join(parts[:i]).lower()
            pv = vid_by_dir.get(parent, [])
            if i == len(parts) - 2:   # Subs\<video stem>\file
                pv = [r for r in pv if stem_of(r).lower() == parts[-1].lower()]
                em = EP_RE.search(parts[-1])
                if not pv and em:   # Show\Subs\Show.S03E01.WEBRip\2_English.srt -> video anywhere under Show\ with same SxxEyy
                    code = (int(em[1] or em[4]), int(em[2] or em[5]))
                    def vcode(r):
                        mm = EP_RE.search(stem_of(r)); return mm and (int(mm[1] or mm[4]), int(mm[2] or mm[5]))
                    pv = [r for r in vids.values() if r['old_path'].lower().startswith(parent + '\\') and vcode(r) == code]
            if len(pv) == 1:
                v = pv[0]; ls = lang_suffix(ntpath.splitext(fn)[0])
                suffix = (ls + ntpath.splitext(fn)[1].lower()) if ls else None
                if not ls: row['note'] = 'sidecar: unknown language in name; left in place'
        if v and suffix:
            base = v['new_path'] or v['old_path']
            np_ = ntpath.splitext(base)[0] + suffix
            row.update(tmdb_id=v['tmdb_id'], confidence=v['confidence'] or 'high')
            if np_.lower() in taken or (np_.lower() in existing and np_.lower() != p.lower()): row['note'] = 'DUPLICATE sidecar target (same language already placed); left in place'
            elif np_ == p: row['note'] = 'sidecar already correctly named'
            else:
                row['new_path'] = np_; taken[np_.lower()] = p
                row['note'] = 'sidecar of ' + ntpath.basename(v['old_path']) + ('' if v['new_path'] else ' (video not moved)')
        elif not row['note']: row['note'] = 'sidecar: no matching video; left in place'
        rows.append(row)
    with open(a.output, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.DictWriter(f, fieldnames=['old_path', 'new_path', 'media_type', 'tmdb_id', 'confidence', 'note'])
        w.writeheader(); w.writerows(rows)
    c = lambda pred: sum(1 for r in rows if pred(r))
    print(f'{len(rows)} rows -> {a.output}: high={c(lambda r: r["confidence"]=="high" and r["new_path"])} '
          f'low={c(lambda r: r["confidence"]=="low" and r["new_path"])} skipped/unmatched={c(lambda r: not r["new_path"])}')

if __name__ == '__main__': main()
