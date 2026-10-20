# Copyright (C) 2026 JeepNWilly
# Renamr is free software: you can redistribute it and/or modify it under the terms of the
# GNU General Public License as published by the Free Software Foundation, either version 3
# of the License, or (at your option) any later version. It comes with no warranty.
# See the LICENSE file in the repository root or <https://www.gnu.org/licenses/>.
# Renamr engine - faithful port of plan.py + apply/undo logic. Windows PowerShell 5.1 and PowerShell 7 compatible.
# No UI code here. The GUI (Renamr.ps1) loads this into a background runspace.
# Paths are always Windows-style (backslash) strings; path helpers below do not depend on the host OS.

$script:PR_ENGINE_CODE = $null; if ($PSCommandPath -and $PSCommandPath -like '*Renamr.Engine.ps1') { try { $script:PR_ENGINE_CODE = [IO.File]::ReadAllText($PSCommandPath) } catch { } }   # for the parallel lookups (the GUI sets it from its own copy)
$script:PR_VIDEO   = @('.mkv','.mp4','.avi','.m4v','.mov','.wmv','.mpg','.mpeg','.ts','.m2ts','.webm','.flv','.divx')
$script:PR_SIDECAR = @('.srt','.sub','.idx','.ass','.ssa','.vtt','.smi','.nfo')
$script:PR_TAGS = @{}
foreach ($t in (@'
480p 576p 720p 1080p 1080i 2160p 4k uhd hdr hdr10 dv sdr x264 x265 h264 h265 hevc avc xvid divx 10bit 8bit
bluray blu-ray brrip bdrip webrip web-dl webdl web hdtv pdtv dvdrip dvdscr dvd scr screener cam ts tc hdcam r5 hdrip remux
aac aac2 ac3 dts dd5 ddp5 atmos truehd mp3 extended ext hc anime dual audio ita eng dlmux anniversary unrated remastered directors cut dc theatrical imax proper repack
internal limited multi subbed dubbed complete criterion edition uncut rarbg yts yify eztv ettv amzn nf hulu dsnp hmax
'@ -split '\s+')) { if ($t) { $script:PR_TAGS[$t] = $true } }
$script:PR_ILLEGAL = '[<>"/\\|?*\x00-\x1f]'
$script:PR_EP  = [regex]'(?i)(?<![a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?:[ ._-]*-?e(\d{1,3}))?(?![a-z0-9])|(?<![a-z0-9])(\d{1,2})x(\d{2,3})(?![a-z0-9])'
$script:PR_ABS = [regex]'(?i)^(.*?)\s-\s(\d{1,3})(?!\d)|^(.*?)[ ._-]part[ ._](\d{1,2})(?!\d)'
$script:PR_SKIP = [regex]'(?i)\\(Plex Versions|ROMS|@eaDir|#recycle)\\'
$script:PR_YEAR_FULL = '^(19[2-9]\d|20[0-4]\d)$'
$script:PR_LANG = @{ english='en'; eng='en'; spanish='es'; spa='es'; french='fr'; fre='fr'; fra='fr'; german='de'; ger='de'; deu='de';
  italian='it'; ita='it'; portuguese='pt'; por='pt'; brazilian='pt-BR'; dutch='nl'; dut='nl'; russian='ru'; rus='ru'; japanese='ja';
  jpn='ja'; korean='ko'; kor='ko'; chinese='zh'; chi='zh'; zho='zh'; arabic='ar'; ara='ar'; hebrew='he'; heb='he'; polish='pl'; pol='pl';
  swedish='sv'; swe='sv'; norwegian='no'; nor='no'; nob='nb'; danish='da'; dan='da'; finnish='fi'; fin='fi'; greek='el'; gre='el';
  ell='el'; turkish='tr'; tur='tr'; czech='cs'; cze='cs'; ces='cs'; hungarian='hu'; hun='hu'; romanian='ro'; rum='ro'; ron='ro'; thai='th';
  tha='th'; vietnamese='vi'; vie='vi'; indonesian='id'; ind='id'; malay='ms'; may='ms'; msa='ms'; hindi='hi'; hin='hi'; ukrainian='uk';
  ukr='uk'; croatian='hr'; hrv='hr'; bulgarian='bg'; bul='bg'; slovak='sk'; slo='sk'; slovenian='sl'; slv='sl'; catalan='ca'; cat='ca';
  basque='eu'; baq='eu'; galician='gl'; glg='gl'; icelandic='is'; ice='is'; estonian='et'; est='et'; latvian='lv'; lav='lv';
  lithuanian='lt'; lit='lt'; filipino='fil'; fil='fil'; tamil='ta'; tam='ta'; telugu='te'; tel='te'; persian='fa'; per='fa';
  serbian='sr'; srp='sr'; kannada='kn'; kan='kn'; malayalam='ml'; mal='ml'; bengali='bn'; bokmal='nb' }
$script:PRSync = $null   # optional synchronized hashtable from the GUI: Log (ConcurrentQueue[string]), Done, Total, Cancel

function PR-Log([string]$msg) {
    if ($script:PRSync) { $script:PRSync.Log.Enqueue(("{0:HH:mm:ss} {1}" -f (Get-Date), $msg)) } else { Write-Host $msg }
}
function PR-Progress([int]$done, [int]$total, [string]$phase) {
    if ($script:PRSync) { $script:PRSync.Done = $done; $script:PRSync.Total = $total; $script:PRSync.Phase = $phase }
}
function PR-Cancelled { return ($script:PRSync -and $script:PRSync.Cancel) }

# ---------- string similarity: exact port of Python difflib.SequenceMatcher(None,a,b).ratio() ----------
$prDiffSrc = @'
using System; using System.Collections.Generic;
public static class PRDiff {
  public static double Ratio(string a, string b) {
    int la = a.Length, lb = b.Length;
    if (la + lb == 0) return 1.0;
    var b2j = new Dictionary<char, List<int>>();
    for (int j = 0; j < lb; j++) { List<int> l; if (!b2j.TryGetValue(b[j], out l)) { l = new List<int>(); b2j[b[j]] = l; } l.Add(j); }
    if (lb >= 200) { int ntest = lb / 100 + 1; var pop = new List<char>(); foreach (var kv in b2j) if (kv.Value.Count > ntest) pop.Add(kv.Key); foreach (var c in pop) b2j.Remove(c); }
    return 2.0 * Blocks(a, b, b2j, 0, la, 0, lb) / (la + lb);
  }
  static int Blocks(string a, string b, Dictionary<char, List<int>> b2j, int alo, int ahi, int blo, int bhi) {
    int besti = alo, bestj = blo, bestsize = 0;
    var j2len = new Dictionary<int, int>();
    for (int i = alo; i < ahi; i++) {
      var newj2len = new Dictionary<int, int>(); List<int> js;
      if (b2j.TryGetValue(a[i], out js)) foreach (int j in js) {
        if (j < blo) continue; if (j >= bhi) break;
        int prev; j2len.TryGetValue(j - 1, out prev); int k = prev + 1; newj2len[j] = k;
        if (k > bestsize) { besti = i - k + 1; bestj = j - k + 1; bestsize = k; }
      }
      j2len = newj2len;
    }
    while (besti > alo && bestj > blo && a[besti - 1] == b[bestj - 1]) { besti--; bestj--; bestsize++; }
    while (besti + bestsize < ahi && bestj + bestsize < bhi && a[besti + bestsize] == b[bestj + bestsize]) bestsize++;
    if (bestsize == 0) return 0;
    int total = bestsize;
    if (alo < besti && blo < bestj) total += Blocks(a, b, b2j, alo, besti, blo, bestj);
    if (besti + bestsize < ahi && bestj + bestsize < bhi) total += Blocks(a, b, b2j, besti + bestsize, ahi, bestj + bestsize, bhi);
    return total;
  }
}
'@
if (-not ('PRDiff' -as [type])) { Add-Type -TypeDefinition $prDiffSrc -Language CSharp }

function PR-Norm([string]$s) {
    if ($null -eq $s) { $s = '' }
    $d = $s.Normalize([Text.NormalizationForm]::FormKD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) { if ([int]$ch -lt 128) { [void]$sb.Append($ch) } }
    $t = $sb.ToString().ToLowerInvariant().Replace('&', 'and')
    return ([regex]::Replace($t, '[^a-z0-9]+', ' ')).Trim()
}
function PR-Spell([string]$s) { if ($null -eq $s) { return '' }; try { $s = $s.Normalize([Text.NormalizationForm]::FormC) } catch { }; return ([regex]::Replace($s.ToLowerInvariant(), '[^\p{L}\p{N}]+', ' ')).Trim() }   # keeps accents: 'Rédemption' <> 'Redemption'
function PR-SameSpelling([string]$a, [string]$b) { $x = PR-Spell $a; return ($x -and $x -ceq (PR-Spell $b)) }
function PR-Sim([string]$a, [string]$b) { return [PRDiff]::Ratio((PR-Norm $a), (PR-Norm $b)) }
function PR-F2([double]$x) { return $x.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture) }
function PR-D2([int]$x) { return $x.ToString('00') }

function PR-StripYear([string]$name) {
    # TVDB titles are sometimes disambiguated like "Last Man Standing (2011)"; the year is added again when the name is built
    return ([regex]::Replace($name, '\s*\((?:19|20)\d\d\)\s*$', '')).Trim()
}
function PR-Safe([string]$name) {
    # compatibility characters become plain ones (Alien³ -> Alien3, ligatures, full-width forms); trademark signs are dropped
    $name = $name.Replace([string][char]0x2122, '').Replace([string][char]0x00AE, '').Replace([string][char]0x00A9, '')
    try { $name = $name.Normalize([System.Text.NormalizationForm]::FormKC) } catch { }
    $name = $name.Replace([string][char]0x2044, '-')
    $rep = ' - '; if ($name.Contains(' - ')) { $rep = ' ' }
    $name = $name.Replace(': ', $rep).Replace(':', '-')
    $name = [regex]::Replace($name, $script:PR_ILLEGAL, '')
    $name = ([regex]::Replace($name, '\s+', ' ')).Trim()
    return $name.TrimEnd('.', ' ')
}

# ---------- Windows path helpers (host-OS independent, mirror Python ntpath) ----------
function PR-Dir([string]$p) { $i = $p.LastIndexOf('\'); if ($i -lt 0) { return '' }; $d = $p.Substring(0, $i); if ($d -match '^[A-Za-z]:$') { $d += '\' }; return $d }
function PR-Base([string]$p) { $i = $p.LastIndexOf('\'); return $p.Substring($i + 1) }
function PR-SplitExt([string]$p) {
    # returns @(root, ext) like ntpath.splitext
    $b = PR-Base $p; $i = $b.LastIndexOf('.')
    if ($i -le 0 -or $b.Substring(0, $i).Trim('.') -eq '') { return @($p, '') }
    $cut = $p.Length - ($b.Length - $i)
    return @($p.Substring(0, $cut), $p.Substring($cut))
}
function PR-Join { $out = $args[0]; for ($k = 1; $k -lt $args.Count; $k++) { if ($out.EndsWith('\')) { $out += $args[$k] } else { $out += '\' + $args[$k] } }; return $out }
function PR-Under([string]$p, [string]$root) { if (-not $root) { return $false }; return $p.ToLowerInvariant().StartsWith($root.ToLowerInvariant() + '\', [StringComparison]::Ordinal) }

# ---------- filename parsing ----------
function PR-CleanTokens([string]$text, [switch]$NoBreak) {
    $text = [regex]::Replace($text, '\[[^\]]*\]|\{[^}]*\}', ' ')
    $text = [regex]::Replace($text, '(?i)\b\d+(st|nd|rd|th)[ ._]anniversary\b', ' anniversary')
    $text = [regex]::Replace($text, '-(?=(19|20)\d\d(\D|$))', ' ')
    $text = [regex]::Replace($text, '[._]+', ' ')
    $text = [regex]::Replace($text, '\s-\s?[A-Za-z0-9]+$', ' ')
    $toks = ($text.Replace('(', ' ').Replace(')', ' ')).Trim() -split '\s+'
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($t in $toks) {
        if ($t -eq '') { continue }
        $tl = $t.ToLowerInvariant().Trim('-')
        $base = $tl.Split('-')[0]
        if (-not $NoBreak -and ($script:PR_TAGS.ContainsKey($tl) -or $script:PR_TAGS.ContainsKey($base) -or $tl -match '^\d{3,4}p$')) { break }
        $out.Add($t)
    }
    return ,$out.ToArray()
}
function PR-ParseMovie([string]$stem) {
    $stem = [regex]::Replace($stem, '^\d{1,2}[ ._-]+(?=[A-Za-z])', '')
    $toks = PR-CleanTokens $stem
    $year = $null; $title = $toks
    for ($i = $toks.Count - 1; $i -gt 0; $i--) {
        if ($toks[$i] -match $script:PR_YEAR_FULL) { $year = [int]$toks[$i]; $title = $toks[0..($i - 1)]; break }
    }
    if ($null -eq $year) {
        # 'Title - Extended Edition (2004) 720p': an edition word (extended, uncut, remastered...) ends the title early and would hide the year that follows it
        $all = PR-CleanTokens $stem -NoBreak
        $lim = $all.Count; for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -match '^\d{3,4}p$') { $lim = $i; break } }
        for ($i = $lim - 1; $i -ge $toks.Count -and $i -gt 0; $i--) { if ($all[$i] -match $script:PR_YEAR_FULL) { $year = [int]$all[$i]; break } }
    }
    return @{ Title = (($title -join ' ').Trim(' ', '-')); Year = $year }
}
function PR-ParseShow([string]$text) {
    $toks = PR-CleanTokens $text
    while ($toks.Count -gt 1 -and $toks[-1] -match '^-+$') { $toks = @($toks[0..($toks.Count - 2)]) }   # 'Show 2023 - S01E01': the dash before SxxEyy must not hide the year
    $year = $null
    if ($toks.Count -gt 1 -and $toks[-1] -match $script:PR_YEAR_FULL) { $year = [int]$toks[-1]; $toks = @($toks[0..($toks.Count - 2)]) }
    return @{ Title = (($toks -join ' ').Trim(' ', '-')); Year = $year }
}

# ---------- TMDB client with JSON cache (same cache keys as plan.py) ----------
function PR-QuotePlus([string]$s) {
    $sb = New-Object Text.StringBuilder
    foreach ($byte in [Text.Encoding]::UTF8.GetBytes($s)) {
        $c = [char]$byte
        if (($byte -ge 48 -and $byte -le 57) -or ($byte -ge 65 -and $byte -le 90) -or ($byte -ge 97 -and $byte -le 122) -or '_.-~'.Contains([string]$c)) { [void]$sb.Append($c) }
        elseif ($byte -eq 32) { [void]$sb.Append('+') }
        else { [void]$sb.Append('%' + $byte.ToString('X2')) }
    }
    return $sb.ToString()
}
function PR-UrlEncode($params) {
    $keys = @($params.Keys | ForEach-Object { [string]$_ }); [Array]::Sort($keys, [StringComparer]::Ordinal)
    return (($keys | ForEach-Object { (PR-QuotePlus $_) + '=' + (PR-QuotePlus ([string]$params[$_])) }) -join '&')
}
function PR-Trim($path, $data) {
    # keep only fields the engine uses so the cache stays small
    if ($null -eq $data) { return $null }
    if ($path -like '/find/*') {
        $mv = @(); foreach ($r in @($data.movie_results)) { if ($null -ne $r) { $mv += [pscustomobject]@{ id = $r.id } } }
        $tv = @(); foreach ($r in @($data.tv_results)) { if ($null -ne $r) { $tv += [pscustomobject]@{ id = $r.id } } }
        return [pscustomobject]@{ movie_results = $mv; tv_results = $tv }
    }
    if ($path -like '*/alternative_titles') {
        $res = @(); foreach ($r in @($data.titles) + @($data.results)) { if ($null -ne $r -and $r.iso_3166_1) { $res += [pscustomobject]@{ iso_3166_1 = [string]$r.iso_3166_1; title = [string]$r.title; type = [string]$r.type } } }
        return [pscustomobject]@{ titles = $res }
    }
    if ($path -like '/search/*') {
        $res = @(); foreach ($r in @($data.results)) { if ($null -eq $r) { continue }
            $o = [ordered]@{ id = $r.id; popularity = $r.popularity }
            foreach ($f in 'title','original_title','release_date','name','original_name','first_air_date') { if ($null -ne $r.$f) { $o[$f] = $r.$f } }
            $res += [pscustomobject]$o }
        return [pscustomobject]@{ results = $res }
    }
    if ($path -match '^/(movie|tv)/\d+$') { $o = [ordered]@{ id = $data.id }; foreach ($f in 'title','original_title','release_date','name','original_name','first_air_date') { if ($null -ne $data.$f) { $o[$f] = $data.$f } }; return [pscustomobject]$o }   # details (search by id)
    $eps = @(); foreach ($e in @($data.episodes)) { if ($null -ne $e) { $eps += [pscustomobject]@{ episode_number = $e.episode_number; name = $e.name } } }
    return [pscustomobject]@{ episodes = $eps }
}
$script:PR_US_TITLES = $true   # Setup: Use US titles (TMDB asked in en-US / region US, US release title preferred)
function New-PRTmdb([string]$Key, [string]$CachePath, [string]$TvdbKey = '', [string]$TvdbPin = '', [string]$Source = 'Movies: TMDB, TV: TVDB', $UsTitles = $null) {
    if ($null -eq $UsTitles) { $UsTitles = [bool]$script:PR_US_TITLES }
    $cache = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    if ($CachePath -and (Test-Path -LiteralPath $CachePath)) {
        try {
            # stored as [{"k":key,"v":value},...] because PS 5.1 ConvertFrom-Json rejects keys differing only by case
            $obj = [IO.File]::ReadAllText($CachePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($e in @($obj)) { if ($null -ne $e) { $cache[[string]$e.k] = $e.v } }
        } catch { PR-Log "Cache unreadable, starting fresh: $($_.Exception.Message)" }
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    return @{ Key = $Key; CachePath = $CachePath; Cache = $cache; Last = [Diagnostics.Stopwatch]::StartNew(); Dirty = 0; Calls = 0; Source = $Source; UsTitles = [bool]$UsTitles; GapMs = 30; TmdbBase = 'https://api.themoviedb.org/3'; Collect = $null; Tvdb = @{ Key = $TvdbKey; Pin = $TvdbPin; Token = ''; Stamp = [Diagnostics.Stopwatch]::StartNew() } }
}
function Save-PRTmdbCache($db) {
    if (-not $db.CachePath) { return }
    $tmp = $db.CachePath + '.tmp'
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($kv in $db.Cache.GetEnumerator()) { $list.Add([pscustomobject]@{ k = $kv.Key; v = $kv.Value }) }
    $json = ConvertTo-Json -InputObject $list.ToArray() -Depth 8 -Compress
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $db.CachePath) { [IO.File]::Delete($db.CachePath) }
    [IO.File]::Move($tmp, $db.CachePath); $db.Dirty = 0
}
function PR-TmdbGet($db, [string]$path, $params) {
    $clean = @{}
    foreach ($k in $params.Keys) { $v = $params[$k]; if ($null -ne $v -and [string]$v -ne '') { $clean[$k] = $v } }
    $ck = $path + '?' + (PR-UrlEncode $clean)
    if ($db.Cache.ContainsKey($ck)) { return $db.Cache[$ck] }
    if ($null -ne $db.Collect) { $db.Collect[$ck] = @{ Provider = 'tmdb'; Path = $path; Params = $clean }; throw 'PRCollect' }   # prefetch discovery: note the request, stop this lookup
    if (-not $db.Key) { throw "TMDB key missing and $ck not in cache" }
    $q = @{}; foreach ($k in $clean.Keys) { $q[$k] = $clean[$k] }; $q['api_key'] = $db.Key
    $url = $db.TmdbBase + $path + '?' + (PR-UrlEncode $q)
    $data = $null; $ok = $false
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $wait = $db.GapMs - $db.Last.ElapsedMilliseconds; if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }   # ~30 req/s (each parallel worker gets a share)
        $db.Last.Restart(); $db.Calls++
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
            $data = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
            $ok = $true; break
        } catch {
            $code = 0; $retry = $null
            try { $code = [int]$_.Exception.Response.StatusCode } catch {}
            try { $retry = $_.Exception.Response.Headers['Retry-After'] } catch {}
            if (-not $retry) { try { $retry = ($_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds) } catch {} }
            if ($code -eq 404) { $data = $null; $ok = $true; break }
            if ($code -eq 401) { throw 'TMDB rejected the API key (HTTP 401)' }
            if ($code -eq 429 -or $code -ge 500 -or $code -eq 0) {
                $sec = [math]::Pow(2, $attempt); if ($retry) { $sec = [double]("$retry".Split(',')[0]) }
                Start-Sleep -Milliseconds ([int](1000 * $sec)); continue
            }
            throw "TMDB HTTP $code on $path"
        }
    }
    if (-not $ok) { throw "TMDB unreachable for $path" }
    $data = PR-Trim $path $data
    $db.Cache[$ck] = $data; $db.Dirty++
    if ($db.Dirty -ge 50) { Save-PRTmdbCache $db }
    return $data
}
# ---------- TheTVDB v4 client (results are reshaped to look like TMDB results so the matcher is shared) ----------
function PR-TvdbToken($db) {
    $t = $db.Tvdb
    if ($t.Token -and $t.Stamp.Elapsed.TotalHours -lt 20) { return $t.Token }
    $body = @{ apikey = $t.Key }; if ($t.Pin) { $body['pin'] = $t.Pin }
    try {
        $resp = Invoke-WebRequest -Uri 'https://api4.thetvdb.com/v4/login' -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Compress) -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $j = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
        $t.Token = [string]$j.data.token; $t.Stamp = [Diagnostics.Stopwatch]::StartNew()
    } catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        if ($code -eq 401) { throw 'TVDB rejected the API key or PIN (HTTP 401)' }
        throw "TVDB login failed: $($_.Exception.Message)"
    }
    return $t.Token
}
function PR-TvdbRaw($db, [string]$path, $params) {
    # returns parsed JSON or $null on 404; retries on 429/5xx; one re-login on 401
    $q = ''; if ($params -and $params.Count) { $q = '?' + (PR-UrlEncode $params) }
    $url = 'https://api4.thetvdb.com/v4' + $path + $q
    $relogin = $false
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $tok = PR-TvdbToken $db
        $wait = 100 - $db.Last.ElapsedMilliseconds; if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
        $db.Last.Restart(); $db.Calls++
        try {
            $resp = Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Bearer $tok" } -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            return ([Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json)
        } catch {
            $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
            if ($code -eq 404) { return $null }
            if ($code -eq 401 -and -not $relogin) { $relogin = $true; $db.Tvdb.Token = ''; continue }
            if ($code -eq 401) { throw 'TVDB rejected the API key (HTTP 401)' }
            if ($code -eq 429 -or $code -ge 500 -or $code -eq 0) { Start-Sleep -Milliseconds ([int](1000 * [math]::Pow(2, $attempt))); continue }
            throw "TVDB HTTP $code on $path"
        }
    }
    throw "TVDB unreachable for $path"
}
function PR-TvdbSearch($db, [string]$type, [string]$query, $year) {
    $p = @{ query = $query; type = $type; limit = 10 }; if ($year) { $p['year'] = [string]$year }
    $j = PR-TvdbRaw $db '/search' $p
    $res = @()
    if ($j -and $j.data) {
        foreach ($r in @($j.data)) {
            if ($null -eq $r) { continue }
            $id = [string]$r.tvdb_id; if (-not $id) { $id = ([string]$r.id) -replace '^[a-z]+-', '' }
            if (-not $id) { continue }
            $orig = [string]$r.name; $eng = $orig
            try { if ($r.translations -and $r.translations.eng) { $eng = [string]$r.translations.eng } } catch {}
            if (-not $eng -and $r.name_translated) { $eng = [string]$r.name_translated }
            $eng = PR-StripYear $eng; $orig = PR-StripYear $orig
            $y = [string]$r.year; if (-not $y -and $r.first_air_time) { $y = ([string]$r.first_air_time).Substring(0, [math]::Min(4, ([string]$r.first_air_time).Length)) }
            $d = ''; if ($y -match '^\d{4}$') { $d = "$y-01-01" }
            if ($type -eq 'movie') { $res += [pscustomobject]@{ id = $id; title = $eng; original_title = $orig; release_date = $d; popularity = 0 } }
            else { $res += [pscustomobject]@{ id = $id; name = $eng; original_name = $orig; first_air_date = $d; popularity = 0 } }
        }
    }
    return [pscustomobject]@{ results = $res }
}
function PR-TvdbSeason($db, [string]$id, [int]$season) {
    $eps = New-Object System.Collections.Generic.List[object]
    foreach ($lang in 'eng', '') {
        $eps.Clear(); $page = 0; $named = 0
        while ($true) {
            $path = "/series/$id/episodes/default"; if ($lang) { $path += "/$lang" }
            $j = PR-TvdbRaw $db $path @{ page = $page; season = $season }
            if (-not $j -or -not $j.data) { break }
            $list = @(); if ($j.data.episodes) { $list = @($j.data.episodes) } elseif ($j.data.series -and $j.data.series.episodes) { $list = @($j.data.series.episodes) }
            foreach ($e in $list) {
                if ($null -eq $e -or [int]$e.seasonNumber -ne $season) { continue }
                $nm = [string]$e.name; if ($nm) { $named++ }
                $eps.Add([pscustomobject]@{ episode_number = [int]$e.number; name = $nm })
            }
            $next = $null; try { $next = $j.links.next } catch {}
            if ($null -eq $next -or [string]$next -eq '' -or $list.Count -eq 0) { break }
            $page = [int]$next
        }
        if ($named -gt 0 -or $eps.Count -eq 0 -and $lang -eq '') { break }
    }
    return [pscustomobject]@{ episodes = @($eps.ToArray()) }
}
function PR-TvdbGet($db, [string]$path, $params) {
    # same paths as TMDB; cached under a 'tvdb|' key
    $clean = @{}; foreach ($k in $params.Keys) { $v = $params[$k]; if ($null -ne $v -and [string]$v -ne '') { $clean[$k] = $v } }
    $ck = 'tvdb|' + $path + '?' + (PR-UrlEncode $clean)
    if ($db.Cache.ContainsKey($ck)) { return $db.Cache[$ck] }
    if ($null -ne $db.Collect) { $db.Collect[$ck] = @{ Provider = 'tvdb'; Path = $path; Params = $clean }; throw 'PRCollect' }
    if (-not $db.Tvdb.Key) { throw "TVDB key missing and $ck not in cache" }
    $data = $null
    if ($path -eq '/search/movie') { $data = PR-TvdbSearch $db 'movie' ([string]$clean['query']) $clean['primary_release_year'] }
    elseif ($path -eq '/search/tv') { $data = PR-TvdbSearch $db 'series' ([string]$clean['query']) $clean['first_air_date_year'] }
    elseif ($path -match '^/tv/(\d+)/season/(\d+)$') { $data = PR-TvdbSeason $db $Matches[1] ([int]$Matches[2]) }
    else { throw "TVDB: unsupported path $path" }
    $db.Cache[$ck] = $data; $db.Dirty++
    if ($db.Dirty -ge 50) { Save-PRTmdbCache $db }
    return $data
}
function PR-Api($db, [string]$provider, [string]$path, $params) {
    if ($provider -eq 'tvdb') { return (PR-TvdbGet $db $path $params) }
    if ($db.UsTitles) {   # US English names; the language / region are part of the cache key, so US and non-US results never mix
        $q = @{}; if ($params) { foreach ($k in $params.Keys) { $q[$k] = $params[$k] } }
        $q['language'] = 'en-US'; if ($path -eq '/search/movie') { $q['region'] = 'US' }
        $params = $q
    }
    return (PR-TmdbGet $db $path $params)
}
function PR-AltTitles($db, [string]$provider, [string]$kind, $id) {
    # TMDB's US and GB English alternative titles of a film / show (one cached call); empty when off or not TMDB
    if (-not $db.UsTitles -or $provider -ne 'tmdb' -or -not $id) { return @() }
    $j = $null; try { $j = PR-TmdbGet $db "/$kind/$id/alternative_titles" @{} } catch { if ($_.Exception.Message -eq 'PRCollect') { throw }; return @() }
    if (-not $j) { return @() }
    return @(@($j.titles) | Where-Object { $_ -and ($_.iso_3166_1 -eq 'US' -or $_.iso_3166_1 -eq 'GB') -and $_.title } | ForEach-Object { [string]$_.title })
}
function PR-NameTitle($db, [string]$provider, [string]$kind, $id, [string]$Main, [string]$FileTitle) {
    # the name to use: always TMDB's main (en-US) title, except when the file's own title is exactly one of the film's US / GB
    # alternative titles and not the main title ('Redemption' for 136418 'Hummingbird'): then that title is kept. Never substitutes on its own.
    if (-not $FileTitle) { return $Main }
    $fs = PR-Spell $FileTitle; if (-not $fs -or $fs -ceq (PR-Spell $Main)) { return $Main }
    foreach ($a in (PR-AltTitles $db $provider $kind $id)) { if ((PR-Spell $a) -ceq $fs) { return $a } }
    return $Main
}
function PR-Providers($db, [string]$kind = 'movie') {
    # provider order from the Source setting; TVDB only when a key is set (cached TVDB data alone is not used)
    $order = switch ([string]$db.Source) { 'Movies: TMDB, TV: TVDB' { if ($kind -eq 'tv') { @('tvdb', 'tmdb') } else { @('tmdb', 'tvdb') } } 'TVDB first' { @('tvdb', 'tmdb') } 'TMDB only' { @('tmdb') } 'TVDB only' { @('tvdb') } default { @('tmdb', 'tvdb') } }
    $have = @($order | Where-Object { $_ -ne 'tvdb' -or $db.Tvdb.Key })
    if ($have.Count -eq 0) { $have = @('tmdb') }
    return $have
}
function PR-Year($s) { if ($s -and ([string]$s).Length -ge 4) { return [int]([string]$s).Substring(0, 4) }; return $null }

function PR-MatchMovieOne($db, [string]$provider, [string]$title, $year) {
    $best = $null; $sameName = @{}; $topC = New-Object System.Collections.Generic.List[object]
    $ys = @($null); if ($year) { $ys = @($year, $null) }
    foreach ($y in $ys) {
        $resp = PR-Api $db $provider '/search/movie' @{ query = $title; primary_release_year = $y; include_adult = 'false' }
        $res = @(); if ($resp) { $res = @($resp.results) }
        foreach ($r in ($res | Select-Object -First 3)) { if ($r -and $topC.Count -lt 3 -and -not @($topC | Where-Object { [string]$_.id -eq [string]$r.id }).Count) { $topC.Add($r) } }
        foreach ($r in ($res | Select-Object -First 8)) {
            $ry = PR-Year $r.release_date
            $s = [math]::Max((PR-Sim $title ([string]$r.title)), (PR-Sim $title ([string]$r.original_title)))
            if (-not $year -and $ry -and $s -ge 0.9 -and -not $sameName.ContainsKey([int]$ry)) { $sameName[[int]$ry] = (PR-Safe ([string]$r.title)) }
            $yok = ($null -eq $year) -or ($null -ne $ry -and [math]::Abs($ry - $year) -le 1)
            $score = $s
            if ($year -and $ry -eq $year) { $score += 0.15 }
            if ($year -and $ry -and [math]::Abs([int]$ry - [int]$year) -gt 1) { $score -= 0.4 }   # a different show with the same name
            if (-not $yok) { $score -= 0.4 }
            $pop = 0.0; if ($null -ne $r.popularity) { $pop = [double]$r.popularity }
            $score += [math]::Min($pop, 50) / 1000
            if ($s -ge 0.999 -and ((PR-SameSpelling $title ([string]$r.title)) -or (PR-SameSpelling $title ([string]$r.original_title)))) { $score += 0.06 }   # same name with the same accents wins over an accent-only twin (else 'Rédemption' and 'Redemption' swap on every scan)
            if ($ry -and ($null -eq $best -or $score -gt $best.Score)) { $best = @{ Score = $score; R = $r; S = $s; Ry = $ry; Yok = $yok } }
        }
        if ($best -and $best.S -ge 0.85 -and $best.Yok) { break }
    }
    if ($db.UsTitles -and $provider -eq 'tmdb' -and ($null -eq $best -or $best.S -lt 0.85)) {
        # the file's title missed: try the US release titles of the top 3 candidates (at most 3 extra cached calls)
        foreach ($r in $topC) {
            $ry = PR-Year $r.release_date; if (-not $ry) { continue }
            $s = 0.0; foreach ($ut in (PR-AltTitles $db $provider 'movie' $r.id)) { $x = PR-Sim $title $ut; if ($x -gt $s) { $s = $x } }   # matching only: the name still follows PR-NameTitle
            if ($s -lt 0.85 -or ($best -and $s -le $best.S)) { continue }
            $yok = ($null -eq $year) -or ([math]::Abs($ry - $year) -le 1)
            $score = $s; if ($year -and $ry -eq $year) { $score += 0.15 }; if (-not $yok) { $score -= 0.4 }
            $best = @{ Score = $score; R = $r; S = $s; Ry = $ry; Yok = $yok }
        }
    }
    if ($year -and ($null -eq $best -or $best.S -lt 0.6)) {
        $resp = PR-Api $db $provider '/search/movie' @{ query = $title; primary_release_year = $year }
        $res = @(); if ($resp) { $res = @($resp.results) }
        foreach ($r in ($res | Select-Object -First 3)) {
            $rd = [string]$r.release_date; if ($rd.Length -gt 4) { $rd = $rd.Substring(0, 4) }
            $nt = PR-Norm ([string]$r.title)
            if ($rd -eq [string]$year -and $nt -and (PR-Norm $title).StartsWith($nt, [StringComparison]::Ordinal)) {
                return @{ Provider = $provider; Id = $r.id; Title = (PR-Safe $r.title); Year = $year; Conf = 'low'; Note = "partial title match `"$($r.title)`" ($year)" }
            }
        }
    }
    if ($null -eq $best) { return $null }
    $s = $best.S; $ry = $best.Ry; $r = $best.R
    $high = $s -ge 0.9 -and $null -ne $year -and ($ry -eq $year -or ($s -ge 0.97 -and [math]::Abs($ry - $year) -le 1))
    if ($s -lt 0.6) { return $null }
    $note = "matched `"$($r.title)`" ($ry) sim=$(PR-F2 $s)"; if (-not $year) { $note += '; no year in filename' }
    $conf = 'low'; if ($high) { $conf = 'high' }
    $ambig = $false
    if (-not $year -and $sameName.Count -ge 2) {
        # several films share this name (remakes): without a year the pick is only a guess
        $ambig = $true; $conf = 'low'
        $yl = @($sameName.Keys | Sort-Object | Select-Object -First 5 | ForEach-Object { [string]$_ })
        $note += "; AMBIGUOUS: films with this name: $($yl -join ', ') - add the year to the file name"
    }
    if ($provider -eq 'tvdb') { $note = 'TVDB: ' + $note }
    $ttl = PR-NameTitle $db $provider 'movie' $r.id ([string]$r.title) $title
    if ($ttl -cne [string]$r.title) { $note += "; named by the file's own alternative title `"$ttl`"" }
    return @{ Provider = $provider; Id = $r.id; Title = (PR-Safe $ttl); Year = $ry; Conf = $conf; Note = $note; Ambig = $ambig }
}
function PR-MatchShowOne($db, [string]$provider, [string]$name, $year) {
    $best = $null
    $ys = @($null); if ($year) { $ys = @($year, $null) }
    foreach ($y in $ys) {
        $resp = PR-Api $db $provider '/search/tv' @{ query = $name; first_air_date_year = $y }
        $res = @(); if ($resp) { $res = @($resp.results) }
        foreach ($r in ($res | Select-Object -First 8)) {
            $ry = PR-Year $r.first_air_date
            $s = [math]::Max((PR-Sim $name ([string]$r.name)), (PR-Sim $name ([string]$r.original_name)))
            $score = $s
            if ($year -and $ry -eq $year) { $score += 0.15 }
            $pop = 0.0; if ($null -ne $r.popularity) { $pop = [double]$r.popularity }
            $score += [math]::Min($pop, 50) / 500
            if ($s -ge 0.999 -and ((PR-SameSpelling $name ([string]$r.name)) -or (PR-SameSpelling $name ([string]$r.original_name)))) { $score += 0.11 }   # same spelling with accents wins over an accent-only twin
            if ($s -ge 0.999) { $score += 0.2 }   # the exact title beats a partial one ('Supernatural' over 'Neuro - Supernatural Detective'), even with another year
            if ($ry -and ($null -eq $best -or $score -gt $best.Score)) { $best = @{ Score = $score; R = $r; S = $s; Ry = $ry } }
        }
        if ($best -and ($best.S -ge 0.999 -or $null -eq $y)) { break }   # only a partial match for that year: also look without the year
    }
    if ($null -eq $best -or $best.S -lt 0.6) { return $null }
    $nm = [string]$best.R.name; $nm = PR-NameTitle $db $provider 'tv' $best.R.id $nm $name   # main title, or the file's own alternative title
    return @{ Provider = $provider; Id = $best.R.id; Name = (PR-Safe $nm); Year = $best.Ry; Sim = $best.S }
}
function PR-MatchMovie($db, [string]$title, $year) {
    # try providers in order; first high-confidence match wins, else the best low-confidence one
    $keep = $null
    foreach ($pv in (PR-Providers $db)) {
        $m = $null
        try { $m = PR-MatchMovieOne $db $pv $title $year } catch { if ($_.Exception.Message -eq 'PRCollect') { throw }; if ($keep -or $pv -eq 'tvdb') { PR-Log "[$pv] lookup failed for `"$title`": $($_.Exception.Message)"; continue } else { throw } }
        if ($m -and $m.Conf -eq 'high') { return $m }
        if ($m -and -not $keep) { $keep = $m }
    }
    return $keep
}
function PR-MatchShow($db, [string]$name, $year) {
    # first provider with a convincing match wins (name similarity >= 0.85 and, when the file gives a year, a first-air year within 1);
    # otherwise the best of the weaker matches is kept (right year first, then similarity)
    $keep = $null; $keepOk = $false
    foreach ($pv in (PR-Providers $db 'tv')) {
        $m = $null
        try { $m = PR-MatchShowOne $db $pv $name $year } catch { if ($_.Exception.Message -eq 'PRCollect') { throw }; if ($pv -eq 'tvdb') { PR-Log "[tvdb] lookup failed for `"$name`": $($_.Exception.Message)"; continue } else { throw } }
        if (-not $m) { continue }
        $yok = $true; if ($year -and $m.Year) { $yok = ([math]::Abs([int]$m.Year - [int]$year) -le 1) }
        if ($m.Sim -ge 0.85 -and $yok) { return $m }
        if ($null -eq $keep -or ($yok -and -not $keepOk) -or ($yok -eq $keepOk -and $m.Sim -gt $keep.Sim)) { $keep = $m; $keepOk = $yok }
    }
    return $keep
}
function PR-Season($db, $seasons, $tid, [int]$s, [string]$provider = 'tmdb') {
    $k = "$provider|$tid|$s"
    if (-not $seasons.ContainsKey($k)) { $seasons[$k] = PR-Api $db $provider "/tv/$tid/season/$s" @{} }
    # episode map: Map (int -> name) + Order (insertion order, like a Python dict)
    $eps = @{ Map = @{}; Order = (New-Object System.Collections.Generic.List[int]) }
    $data = $seasons[$k]
    if ($data) { foreach ($e in @($data.episodes)) { if ($null -ne $e) { $n = [int]$e.episode_number; if (-not $eps.Map.ContainsKey($n)) { $eps.Order.Add($n) }; $eps.Map[$n] = [string]$e.name } } }
    return $eps
}
function PR-EpGet($eps, $n) { if ($null -ne $n -and $eps.Map.ContainsKey([int]$n)) { return $eps.Map[[int]$n] }; return $null }

function PR-Left8([string]$x) { if ($x.Length -gt 8) { return $x.Substring(0, 8) }; return $x }
function PR-NewRow($p) { return [pscustomobject][ordered]@{ old_path = $p; new_path = ''; media_type = ''; tmdb_id = ''; confidence = ''; note = ''; fold_path = ''; accepted = ''; group_key = ''; query = ''; case_rep = '' } }

# ---------- planner: port of plan.py main() ----------
# ---------- remembered picks (Choose match...), stored in match_overrides.json ----------
# keys: 'movie|f|<file name without extension>' and 'movie|d|<folder name>' (accents kept, case and punctuation ignored), 'show|<show key>';
# saved for the name before and after the rename, so a pick still applies once Renamr has renamed the file
$script:PR_OVR = @{}
function PR-OvrMovieKeys([string]$Path, [string]$MoviesRoot, [bool]$WithDir = $true) {
    $k = New-Object System.Collections.Generic.List[string]
    $st = PR-Spell (PR-SplitExt (PR-Base $Path))[0]; if ($st) { $k.Add('movie|f|' + $st) }
    $d = PR-Dir $Path
    if ($WithDir -and $d -and $d.TrimEnd('\').ToLowerInvariant() -ne ([string]$MoviesRoot).TrimEnd('\').ToLowerInvariant()) { $dn = PR-Spell (PR-Base $d); if ($dn) { $k.Add('movie|d|' + $dn) } }
    return ,$k.ToArray()
}
function PR-OvrShowKey([string]$Path) {
    # the show key a later Scan derives from an episode file name ('Show (2015) - S01E01 - x.mkv' -> show|show|2015)
    $stem = (PR-SplitExt (PR-Base $Path))[0]; $m = $script:PR_EP.Match($stem); if (-not $m.Success) { return $null }
    $c = PR-ParseShow $stem.Substring(0, $m.Index); if (-not $c.Title) { return $null }
    return 'show|' + (PR-Norm $c.Title) + '|' + $c.Year
}
function Find-PROverride([string[]]$Keys) { foreach ($k in $Keys) { if ($k -and $script:PR_OVR.ContainsKey($k)) { return $script:PR_OVR[$k] } }; return $null }
function Import-PROverrides([string]$Path) {
    $script:PR_OVR = @{}
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    try { $arr = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json; foreach ($e in @($arr | ForEach-Object { $_ })) {   # PS 5.1 hands a JSON array over as one object: unroll it
         if ($e -and $e.k -and $e.id) { $script:PR_OVR[[string]$e.k] = [pscustomobject]@{ Provider = [string]$e.provider; Id = $e.id; Title = [string]$e.title; Year = $e.year; Kind = [string]$e.kind } } } }
    catch { PR-Log "Match overrides unreadable, ignored: $($_.Exception.Message)" }
    return $script:PR_OVR.Count
}
function Export-PROverrides([string]$Path) {
    if (-not $Path) { return }
    $list = foreach ($kv in $script:PR_OVR.GetEnumerator()) { [pscustomobject][ordered]@{ k = $kv.Key; kind = $kv.Value.Kind; provider = $kv.Value.Provider; id = $kv.Value.Id; title = $kv.Value.Title; year = $kv.Value.Year } }
    $tmp = $Path + '.tmp'; [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($list) -Depth 4), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Delete($Path) }; [IO.File]::Move($tmp, $Path)
}
function Get-PRRowOvrKeys($Row, [string]$MoviesRoot) {
    # every key that identifies this movie / show, before and after its rename
    $k = New-Object System.Collections.Generic.List[string]
    if ([string]$Row.group_key -like 'show|*') { $k.Add([string]$Row.group_key); foreach ($p in $Row.old_path, $Row.new_path) { if ($p) { $sk = PR-OvrShowKey $p; if ($sk) { $k.Add($sk) } } } }
    else { foreach ($x in (PR-OvrMovieKeys $Row.old_path $MoviesRoot $false)) { $k.Add($x) }; foreach ($p in $Row.new_path, $Row.fold_path) { if ($p) { foreach ($x in (PR-OvrMovieKeys $p $MoviesRoot $true)) { $k.Add($x) } } } }
    return @($k | Select-Object -Unique)
}
function Set-PROverride($Rows, [string]$GroupKey, $Choice, [string]$MoviesRoot) {
    # remembers $Choice for every video row of the group (call with the re-planned rows, so the new names are known)
    $kind = 'movie'; if ($GroupKey -like 'show|*') { $kind = 'show' }
    $v = [pscustomobject]@{ Provider = [string]$Choice.Provider; Id = $Choice.Id; Title = [string]$Choice.Title; Year = $Choice.Year; Kind = $kind }
    $n = 0; foreach ($r in @($Rows | Where-Object { $_.group_key -eq $GroupKey -and $_.media_type -ne 'sidecar' })) { foreach ($k in (Get-PRRowOvrKeys $r $MoviesRoot)) { $script:PR_OVR[$k] = $v; $n++ } }
    return $n
}
function Remove-PROverride($Rows, [string]$GroupKey, [string]$MoviesRoot) {
    # forgets the pick(s) of this group: its own keys, and every other key pointing at the same picked film / show
    $ids = @{}; $keys = @()
    foreach ($r in @($Rows | Where-Object { $_.group_key -eq $GroupKey -and $_.media_type -ne 'sidecar' })) { $keys += @(Get-PRRowOvrKeys $r $MoviesRoot) }
    foreach ($k in $keys) { if ($script:PR_OVR.ContainsKey($k)) { $o = $script:PR_OVR[$k]; $ids["$($o.Kind)|$($o.Provider)|$($o.Id)"] = 1 } }
    $n = 0; foreach ($k in @($script:PR_OVR.Keys)) { $o = $script:PR_OVR[$k]; if ($keys -contains $k -or $ids.ContainsKey("$($o.Kind)|$($o.Provider)|$($o.Id)")) { $script:PR_OVR.Remove($k); $n++ } }
    return $n
}
function Test-PRHasOverride($Rows, [string]$GroupKey, [string]$MoviesRoot) {
    foreach ($r in @($Rows | Where-Object { $_.group_key -eq $GroupKey -and $_.media_type -ne 'sidecar' })) { if (Find-PROverride (Get-PRRowOvrKeys $r $MoviesRoot)) { return $true } }; return $false
}
# ---------- show identity from the show folder (Series\<show>\[Season NN\]episode) ----------
function PR-IsSeasonDirName([string]$n) { return ($n -match '^(?i)(season|series|staffel|saison)[ ._-]*\d{1,3}$' -or $n -match '^(?i)s\d{1,2}$' -or $n -match '^(?i)specials?$') }
function PR-ShowNamesAgree([string]$a, [string]$b) {
    $na = PR-Norm $a; $nb = PR-Norm $b; if (-not $na -or -not $nb) { return $false }
    return ($na -eq $nb -or $na.Contains($nb) -or $nb.Contains($na) -or (PR-Sim $a $b) -ge 0.6)
}
function PR-EpPair($m) {
    # (season, episode) of a PR_EP match, as two numbers
    if ($m.Groups[1].Success) { return @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value) }
    return @([int]$m.Groups[4].Value, [int]$m.Groups[5].Value)
}
function Get-PRShowIdentity([string[]]$Videos, [string]$SeriesRoot) {
    # episode path (lower case) -> @{ Title; Year; Eps; FileYear } for episodes inside a show folder of the Series folder.
    # The show folder names the show; the file name is only the fallback (a stray file, or a folder that is clearly something else).
    # A year in the file name is the show's year only when every episode of the folder has that same year; years that change
    # from season to season ('Supernatural (2007) - S03E01', '(2011) - S07E01') are season years and are not used for matching.
    $out = @{}; $sroot = ([string]$SeriesRoot).TrimEnd('\'); if (-not $sroot) { return $out }
    $dirs = @{}; $files = New-Object System.Collections.Generic.List[object]
    foreach ($p in $Videos) {
        if (-not (PR-Under $p $sroot)) { continue }
        $rel = $p.Substring($sroot.Length + 1).Split('\'); if ($rel.Count -lt 2 -or (PR-IsSeasonDirName $rel[0])) { continue }
        $stem = (PR-SplitExt (PR-Base $p))[0]; $m = $script:PR_EP.Match($stem); if (-not $m.Success) { continue }
        $fc = PR-ParseShow $stem.Substring(0, $m.Index)
        $fd = PR-ParseShow $rel[0]; if (-not $fd.Title) { continue }
        if ($fc.Title -and -not (PR-ShowNamesAgree $fd.Title $fc.Title)) { continue }   # the folder is about something else: keep the file's own name
        $dk = $rel[0].ToLowerInvariant()
        if (-not $dirs.ContainsKey($dk)) { $dirs[$dk] = @{ F = $fd; Years = @{}; Eps = (New-Object System.Collections.Generic.List[object]); Seen = @{} } }
        $d = $dirs[$dk]; $d.Years[[string]$fc.Year] = 1
        $se = PR-EpPair $m; if ($se[0] -gt 0 -and -not $d.Seen.ContainsKey("$($se[0])|$($se[1])")) { $d.Seen["$($se[0])|$($se[1])"] = 1; $d.Eps.Add($se) }
        $files.Add(@($p, $dk, $fc.Year))
    }
    foreach ($f in $files) {
        $d = $dirs[$f[1]]; $y = $d.F.Year
        if (-not $y -and $f[2] -and $d.Years.Count -eq 1) { $y = $f[2] }   # one year on every episode (and none on the folder): the show's year
        $out[$f[0].ToLowerInvariant()] = @{ Title = $d.F.Title; Year = $y; Eps = $d.Eps; FileYear = $f[2] }
    }
    return $out
}
function PR-EpShare($db, $seasons, $sh, $Eps) {
    # share of the folder's episodes (SxxEyy) that the show has (season lists are cached)
    if (-not $sh -or -not $Eps -or $Eps.Count -eq 0) { return 0.0 }
    $prov = [string]$sh.Provider; if (-not $prov) { $prov = 'tmdb' }
    $f = 0; foreach ($se in $Eps) { $eps = PR-Season $db $seasons $sh.Id ([int]$se[0]) $prov; if ($eps.Map.ContainsKey([int]$se[1])) { $f++ } }
    return ($f / $Eps.Count)
}
function PR-MatchShowChecked($db, $seasons, [string]$name, $year, $Eps) {
    # PR-MatchShow, then a check that the show has the folder's episodes; when it has few of them and one of the top 3
    # search results has clearly more, that one is used
    $m = PR-MatchShow $db $name $year
    if (-not $Eps -or $Eps.Count -eq 0) { return $m }
    $sm = 0.0; if ($m) { $sm = PR-EpShare $db $seasons $m $Eps }
    if ($m -and $sm -ge 0.8) { return $m }
    $best = $null; $bs = $sm
    foreach ($c in @(Get-PRCandidates $db 'show' $name $year | Select-Object -First 3)) {
        if (-not $c -or -not $c.Year -or ($m -and [string]$c.Provider -eq [string]$m.Provider -and [string]$c.Id -eq [string]$m.Id)) { continue }
        $cs = PR-EpShare $db $seasons @{ Provider = $c.Provider; Id = $c.Id } $Eps
        if ($cs -gt $bs) { $bs = $cs; $best = $c }
    }
    if ($best -and $bs -ge 0.5 -and $bs -ge $sm + 0.2) {
        $nm = PR-NameTitle $db ([string]$best.Provider) 'tv' $best.Id ([string]$best.Title) $name
        $was = $(if ($m) { "; instead of `"$($m.Name)`" ($($m.Year)), which has $([math]::Round($sm * 100))%" } else { '' })
        return @{ Provider = [string]$best.Provider; Id = $best.Id; Name = (PR-Safe $nm); Year = $best.Year; Sim = [double]$best.Sim; Check = "picked by episodes: has $([math]::Round($bs * 100))% of this folder's episodes$was" }
    }
    return $m
}
function New-PRPlan {
    param([string[]]$Paths, [string]$MoviesRoot, [string]$SeriesRoot, $Db, [bool]$ProbeReal = $true, [bool]$FolderLoose = $true, $Force = @{}, [string[]]$OtherPaths = @())
    if ($null -eq $Force) { $Force = @{} }   # Force: group_key -> match the user chose (Choose match...); OtherPaths: other library files, for clash checks
    $mroot = ''; if ($MoviesRoot) { $mroot = $MoviesRoot.TrimEnd('\') }
    $sroot = ''; if ($SeriesRoot) { $sroot = $SeriesRoot.TrimEnd('\') }
    $paths = @($Paths | ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } | Where-Object { $_ })
    $excluded = 0; $ok = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) { if ($script:PR_SKIP.IsMatch($p)) { $excluded++ } else { $ok.Add($p) } }
    $videos = New-Object System.Collections.Generic.List[string]; $sidecars = New-Object System.Collections.Generic.List[string]
    foreach ($p in $ok) { $e = (PR-SplitExt $p)[1].ToLowerInvariant(); if ($script:PR_VIDEO -contains $e) { $videos.Add($p) } elseif ($script:PR_SIDECAR -contains $e) { $sidecars.Add($p) } }
    PR-Log ("Checked {0} files: {1} videos, {2} subtitle and extra files{3}{4}." -f $paths.Count, $videos.Count, $sidecars.Count, $(if ($excluded) { ", $excluded skipped" } else { "" }), $(if (($ok.Count - $videos.Count - $sidecars.Count) -gt 0) { ", $($ok.Count - $videos.Count - $sidecars.Count) other files left alone" } else { "" }))
    $rows = New-Object System.Collections.Generic.List[object]
    $shows = @{}; $seasons = @{}; $ambig = @{}; $ovHit = @{}
    $ident = Get-PRShowIdentity $videos $sroot
    $n = 0
    foreach ($p in $videos) {
        $n++; if ($n % 10 -eq 0) { PR-Progress $n $videos.Count 'Matching videos' }
        if (PR-Cancelled) { throw 'Cancelled' }
        $fn = PR-Base $p; $se = PR-SplitExt $fn; $stem = $se[0]; $ext = $se[1].ToLowerInvariant()
        $row = PR-NewRow $p
        try {
            $m = $script:PR_EP.Match($stem)
            $absm = $null
            if ((PR-Under $p $sroot) -and -not $m.Success) { $am = $script:PR_ABS.Match($stem.Replace('_', ' ')); if ($am.Success) { $absm = $am } }
            if ((PR-Under $p $sroot) -and -not $m.Success -and -not $absm) {
                $row.media_type = 'episode'; $row.note = 'unmatched: no SxxEyy in name (stray file in Series root?)'; $rows.Add($row); continue
            }
            if ((PR-Under $p $sroot) -or ((PR-Under $p $mroot) -and $m.Success)) {
                $row.media_type = 'episode'
                $extra = New-Object System.Collections.Generic.List[string]
                if (PR-Under $p $mroot) { $extra.Add('episode found under Movies root; planned into Series root') }
                $e2 = $null
                if ($m.Success) {
                    if ($m.Groups[1].Success) { $s = [int]$m.Groups[1].Value; $e1 = [int]$m.Groups[2].Value; if ($m.Groups[3].Success) { $e2 = [int]$m.Groups[3].Value } }
                    else { $s = [int]$m.Groups[4].Value; $e1 = [int]$m.Groups[5].Value }
                    $mstart = $m.Index; $mend = $m.Index + $m.Length
                } else {
                    $s = 1; if ($absm.Groups[2].Success) { $e1 = [int]$absm.Groups[2].Value } else { $e1 = [int]$absm.Groups[4].Value }
                    $extra.Add('no SxxEyy; assumed s01 from absolute/part number - verify')
                    if ($absm.Groups[1].Success) { $mstart = $absm.Groups[1].Length } else { $mstart = $absm.Groups[3].Length }
                    $mend = $absm.Index + $absm.Length
                }
                if (-not $sroot) { $row.note = 'unmatched: episode found but no Series folder selected'; $rows.Add($row); continue }
                $root = $mroot; if (PR-Under $p $sroot) { $root = $sroot }
                $rel = $p.Substring($root.Length + 1).Split('\')
                $cand = PR-ParseShow $stem.Substring(0, $mstart)
                if (-not $cand.Title -and $rel.Count -gt 1) { $cand = PR-ParseShow $rel[0] }
                $fileCand = $cand; $idn = $null; $epsAll = $null
                if ($m.Success -and $ident.ContainsKey($p.ToLowerInvariant())) {   # show named by its folder; every episode of the folder shares one match
                    $idn = $ident[$p.ToLowerInvariant()]; $cand = @{ Title = $idn.Title; Year = $idn.Year }; $epsAll = $idn.Eps
                    if ($idn.FileYear -and $idn.FileYear -ne $idn.Year) { $extraNote = "year $($idn.FileYear) in the file name is the season's year (show taken from its folder)" } else { $extraNote = $null }
                } else { $extraNote = $null }
                $key2 = (PR-Norm $cand.Title) + '|' + $cand.Year
                $row.group_key = 'show|' + $key2; $row.query = "$($cand.Title)|$($cand.Year)"
                if ($Force.ContainsKey($row.group_key) -and -not $shows.ContainsKey($key2)) { $fc = $Force[$row.group_key]; $fcn = PR-NameTitle $Db ([string]$fc.Provider) 'tv' $fc.Id ([string]$fc.Title) $cand.Title; $shows[$key2] = @{ Provider = [string]$fc.Provider; Id = $fc.Id; Name = (PR-Safe $fcn); Year = $fc.Year; Sim = 1.0 } }
                if (-not $shows.ContainsKey($key2) -and -not $Force.ContainsKey($row.group_key)) {
                    $ov = Find-PROverride @($row.group_key, (PR-OvrShowKey $p))
                    if ($ov) { $ovn = PR-NameTitle $Db ([string]$ov.Provider) 'tv' $ov.Id ([string]$ov.Title) $cand.Title; $shows[$key2] = @{ Provider = [string]$ov.Provider; Id = $ov.Id; Name = (PR-Safe $ovn); Year = $ov.Year; Sim = 1.0; Pick = $true } }
                }
                if (-not $shows.ContainsKey($key2)) {
                    if ($idn) {
                        $shows[$key2] = PR-MatchShowChecked $Db $seasons $cand.Title $cand.Year $epsAll
                        if (-not $shows[$key2] -and $fileCand.Title -and (PR-Norm $fileCand.Title) -ne (PR-Norm $cand.Title)) { $shows[$key2] = PR-MatchShow $Db $fileCand.Title $fileCand.Year }   # fallback: the file's own name
                    } else {
                        $shows[$key2] = PR-MatchShow $Db $cand.Title $cand.Year
                        if (-not $shows[$key2] -and $rel.Count -gt 1) { $f = PR-ParseShow $rel[0]; $shows[$key2] = PR-MatchShow $Db $f.Title $f.Year }
                    }
                }
                $sh = $shows[$key2]
                if (-not $sh) { $row.note = "unmatched: no TMDB show for `"$($cand.Title)`""; $rows.Add($row); continue }
                $tid = $sh.Id; $sname = PR-StripYear ([string]$sh.Name); $sy = $sh.Year; $ssim = $sh.Sim
                $prov = [string]$sh.Provider; if (-not $prov) { $prov = 'tmdb' }
                $eps = PR-Season $Db $seasons $tid $s $prov
                $ftitle = ((PR-CleanTokens $stem.Substring($mend)) -join ' ').Trim(' ', '-')   # ' - 1080p Bluray': no title left, not '-'
                $notes = New-Object System.Collections.Generic.List[string]
                $notes.Add("show `"$sname`" sim=$(PR-F2 $ssim)"); if ($prov -eq 'tvdb') { $notes.Add('source: TVDB') }; if ($sh.Check) { $notes.Add([string]$sh.Check) }; if ($extraNote) { $notes.Add($extraNote) }; foreach ($x in $extra) { $notes.Add($x) }
                if (($e1 -eq 0 -or -not $eps.Map.ContainsKey($e1)) -and $ftitle -and $s -ne 0) {
                    $sp = PR-Season $Db $seasons $tid 0 $prov
                    $nf = PR-Norm $ftitle
                    $bestc = $null
                    foreach ($en in $sp.Order) {
                        $t = $sp.Map[$en]; $nt = PR-Norm $t
                        $v = PR-Sim $ftitle $t; $alt = 0.0; if ($nt.Length -gt 6 -and $nf.Contains($nt)) { $alt = 1.0 }
                        $sc = [math]::Max($v, $alt)
                        # python max over (score, n) tuples: higher score, tie -> higher episode number
                        if ($null -eq $bestc -or $sc -gt $bestc[0] -or ($sc -eq $bestc[0] -and $en -gt $bestc[1])) { $bestc = @($sc, $en) }
                    }
                    if ($bestc -and $bestc[0] -ge 0.75) {
                        $bn = $bestc[1]; $notes.Add("moved S$(PR-D2 $s)E$(PR-D2 $e1) -> special S00E$(PR-D2 $bn) by title"); $s = 0; $e1 = $bn; $eps = $sp
                    }
                }
                if ($ftitle -and $eps.Order.Count -gt 0 -and $null -eq $e2 -and $eps.Map.ContainsKey($e1) -and (PR-Norm $ftitle) -ne (PR-Norm $sname) -and @($ftitle.Trim() -split '\s+').Count -ge 2) {
                    $bn = $null; $bs = -1.0
                    foreach ($en in $eps.Order) { $v = PR-Sim $ftitle $eps.Map[$en]; if ($v -gt $bs) { $bs = $v; $bn = $en } }
                    if ($bs -ge 0.8 -and $bn -ne $e1 -and (PR-Sim $ftitle ([string](PR-EpGet $eps $e1))) -lt 0.6) {
                        $notes.Add("renumbered e$e1->e$bn by title `"$($eps.Map[$bn])`""); $e1 = $bn
                    }
                }
                $cur = PR-EpGet $eps $e1
                $titlemismatch = [bool]($ftitle -and $cur -and (PR-Sim $ftitle $cur) -lt 0.5 -and -not $ftitle.ToLowerInvariant().StartsWith((PR-Left8 (PR-Norm $cur)), [StringComparison]::Ordinal))
                if ($titlemismatch) { $ft40 = $ftitle; if ($ft40.Length -gt 40) { $ft40 = $ft40.Substring(0, 40) }; $notes.Add("filename title `"$ft40`" differs from TMDB (number kept)") }
                if ($s -eq 0) { $notes.Add('special (Season 00) - verify numbering') }
                $show = "$sname ($sy)"
                $code = "S$(PR-D2 $s)E$(PR-D2 $e1)"; if ($null -ne $e2) { $code += "-E$(PR-D2 $e2)" }
                $title = PR-EpGet $eps $e1
                $t2 = PR-EpGet $eps $e2
                if ($null -ne $e2 -and $t2) { if ($title) { $title = "$title + $t2" } else { $title = $t2 } }
                if (-not $title) { $srcName = 'TMDB'; if ($prov -eq 'tvdb') { $srcName = 'TVDB' }; $notes.Add("episode not found on $srcName") }
                if ($title -and $title -match '^Episode \d+$') { $title = $null }
                $nm = "$show - $code"; if ($title) { $nm += " - $title" }
                $fname = (PR-Safe $nm) + $ext
                $row.new_path = PR-Join $sroot (PR-Safe $show) ("Season " + (PR-D2 $s)) $fname
                $row.tmdb_id = $(if ($prov -eq 'tvdb') { 'tvdb:' + [string]$tid } else { [string]$tid })
                if ($ssim -ge 0.9 -and $title -and $s -and $extra.Count -eq 0) { $row.confidence = 'high' } else { $row.confidence = 'low' }
                $row.note = $notes -join '; '
            } elseif (PR-Under $p $mroot) {
                $row.media_type = 'movie'
                $pm = PR-ParseMovie $stem
                $folderYear = $false
                if (-not $pm.Year -and $pm.Title) {
                    # no year in the file name: use the year of its own folder, e.g. 'Dune (1984)\Dune.mkv' (only when the folder is not the library root and its title fits the file)
                    $pdir = PR-Dir $p
                    if ($pdir.TrimEnd('\').ToLowerInvariant() -ne $mroot.ToLowerInvariant()) {
                        $fp = PR-ParseMovie (PR-Base $pdir)
                        if ($fp.Year -and $fp.Title -and ((PR-Sim $fp.Title $pm.Title) -ge 0.7 -or (PR-Norm $fp.Title).StartsWith((PR-Norm $pm.Title), [StringComparison]::Ordinal) -or (PR-Norm $pm.Title).StartsWith((PR-Norm $fp.Title), [StringComparison]::Ordinal))) { $pm.Year = $fp.Year; $folderYear = $true }
                    }
                }
                $row.group_key = 'movie|' + $p.ToLowerInvariant(); $row.query = "$($pm.Title)|$($pm.Year)"
                $mm = $null
                if ($Force.ContainsKey($row.group_key)) { $fc = $Force[$row.group_key]; $fcn = PR-NameTitle $Db ([string]$fc.Provider) 'movie' $fc.Id ([string]$fc.Title) $pm.Title; $mm = @{ Provider = [string]$fc.Provider; Id = $fc.Id; Title = (PR-Safe $fcn); Year = $fc.Year; Conf = 'low'; Note = "chosen by you: `"$($fc.Title)`" ($($fc.Year))" } }
                elseif ($ov = Find-PROverride (PR-OvrMovieKeys $p $mroot)) { $ovn = PR-NameTitle $Db ([string]$ov.Provider) 'movie' $ov.Id ([string]$ov.Title) $pm.Title; $mm = @{ Provider = [string]$ov.Provider; Id = $ov.Id; Title = (PR-Safe $ovn); Year = $ov.Year; Conf = 'high'; Note = "your pick: `"$ovn`" ($($ov.Year))" }; $ovHit[$p] = 1 }   # remembered Choose match
                elseif ($pm.Title) { $mm = PR-MatchMovie $Db $pm.Title $pm.Year }
                $loose = $FolderLoose -and ((PR-Dir $p).TrimEnd('\').ToLowerInvariant() -eq $mroot.ToLowerInvariant())
                if (-not $mm) {
                    $yr = 'None'; if ($pm.Year) { $yr = $pm.Year }; $row.note = "unmatched: no TMDB movie for `"$($pm.Title)`" ($yr)"
                    if ($loose -and $pm.Title) { $fd = PR-Safe $pm.Title; if ($pm.Year) { $fd = PR-Safe "$($pm.Title) ($($pm.Year))" }; $row.fold_path = PR-Join $mroot $fd (PR-Base $p) }   # still give a loose file its own folder (name kept)
                    $rows.Add($row); continue
                }
                $base = PR-Safe "$(PR-StripYear ([string]$mm.Title)) ($($mm.Year))"
                if ((-not $FolderLoose) -and ((PR-Dir $p).TrimEnd('\').ToLowerInvariant() -eq $mroot.ToLowerInvariant())) { $row.new_path = PR-Join $mroot ($base + $ext) } else { $row.new_path = PR-Join $mroot $base ($base + $ext) }   # option off: a movie loose in the library root is only renamed, not put into its own folder
                $row.tmdb_id = $(if ($mm.Provider -eq 'tvdb') { 'tvdb:' + [string]$mm.Id } else { [string]$mm.Id }); $row.confidence = $mm.Conf; $row.note = $mm.Note
                if ($loose) { $row.fold_path = PR-Join $mroot $base (PR-Base $p) }   # folder-only move (name kept), used when the rename itself is not applied (low confidence with high-only, or a clash)
                if ($folderYear) { $row.note += "; year $($pm.Year) taken from the folder name" }
                if ($mm.Ambig) { $ambig[$p] = $true }
            } else {
                $row.note = 'unmatched: path not under movies or series root'
            }
        } catch {
            if ($_.Exception.Message -eq 'Cancelled') { throw }
            $row.note = "error: $($_.Exception.Message)"
        }
        if ($row.new_path -and ($row.media_type -eq 'movie' -or $row.media_type -eq 'episode')) {
            # keep a resolution tag that was in the old name, but use the real resolution from the file when it differs
            $hint = PR-ResHint $stem
            if ($hint.Rank -gt 0) {
                $lab = $hint.Label
                $real = $null; if ($ProbeReal) { $real = PR-ProbeRes $p }
                if ($real -and $real.Rank -ne $hint.Rank) { $row.note = ("resolution corrected $($hint.Label) -> $($real.Label) (read from file); " + $row.note).TrimEnd(' ', ';'); $lab = $real.Label }
                $ne = PR-SplitExt $row.new_path
                $row.new_path = $ne[0] + ' - ' + $lab + $ne[1]
            }
        }
        $rows.Add($row)
    }
    PR-Progress $videos.Count $videos.Count 'Resolving duplicates'
    Save-PRTmdbCache $Db
    # collisions / already-correct. high-confidence first, then by lowercase path (ordinal), stable
    $existing = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in @($paths) + @($OtherPaths)) { if ($p) { [void]$existing.Add($p.ToLowerInvariant()) } }
    $idx = 0; $keyed = foreach ($r in $rows) { $k = '1'; if ($r.confidence -eq 'high') { $k = '0' }; [pscustomobject]@{ K = $k; P = $r.old_path.ToLowerInvariant(); I = $idx++; R = $r } }
    $arr = [object[]]@($keyed)
    [Array]::Sort($arr, [Comparison[object]]{ param($a, $b)
        $c = [string]::CompareOrdinal($a.K, $b.K); if ($c -ne 0) { return $c }
        $c = [string]::CompareOrdinal($a.P, $b.P); if ($c -ne 0) { return $c }
        return $a.I.CompareTo($b.I) })
    $rows = New-Object System.Collections.Generic.List[object]; foreach ($x in $arr) { $rows.Add($x.R) }
    $taken = @{}; $takenDir = @{}
    # rows whose film was only a guess between same-name films go last, so a file that has a year always keeps its own target
    $ordered = @($rows | Where-Object { -not $ambig.ContainsKey($_.old_path) }) + @($rows | Where-Object { $ambig.ContainsKey($_.old_path) })
    foreach ($r in $ordered) {
        if (-not $r.new_path) { continue }
        if ($r.new_path -ceq $r.old_path) { $r.new_path = ''; $r.note = $(if ($ovHit.ContainsKey($r.old_path)) { 'your pick; ' } else { '' }) + 'already correctly named; skipped'; continue }
        $k = $r.new_path.ToLowerInvariant()
        if ($ambig.ContainsKey($r.old_path) -and ((($existing.Contains($k)) -and ($k -ne $r.old_path.ToLowerInvariant())) -or ($taken.ContainsKey($k) -and -not $ambig.ContainsKey($taken[$k])) -or ($takenDir.ContainsKey((PR-Dir $k)) -and $takenDir[(PR-Dir $k)] -ne $r.old_path))) {
            $r.note = 'POSSIBLE REMAKE: no year in the file name and several films share this name, so it was not renamed (it would clash with another file). Add the year to the name and scan again; ' + $r.note; $r.new_path = ''; $r.confidence = 'low'; continue
        }
        if ($taken.ContainsKey($k)) { $r.note = "DUPLICATE: same target as $($taken[$k]); " + $r.note; $r.new_path = ''; $r.confidence = 'low'; continue }
        if ($existing.Contains($k) -and $k -ne $r.old_path.ToLowerInvariant()) { $r.note = 'COLLISION: target already exists in library; ' + $r.note; $r.new_path = ''; $r.confidence = 'low'; continue }
        $taken[$k] = $r.old_path
        if (-not $ambig.ContainsKey($r.old_path) -and $r.media_type -eq 'movie') { $takenDir[(PR-Dir $k)] = $r.old_path }
    }
    $byFolder = New-Object 'System.Collections.Specialized.OrderedDictionary'
    foreach ($r in $rows) { if ($r.new_path -and $r.media_type -eq 'movie') { $d = (PR-Dir $r.new_path).ToLowerInvariant(); if (-not $byFolder.Contains($d)) { $byFolder.Add($d, (New-Object System.Collections.Generic.List[object])) }; $byFolder[$d].Add($r) } }
    foreach ($g in $byFolder.Values) { if ($g.Count -gt 1) { foreach ($r in $g) { $r.note = "MULTIPLE VERSIONS ($($g.Count) files) of same movie; " + $r.note } } }
    # sidecars
    $vids = New-Object 'System.Collections.Specialized.OrderedDictionary'
    foreach ($r in $rows) { if ($r.media_type -eq 'movie' -or $r.media_type -eq 'episode') { $vids[$r.old_path.ToLowerInvariant()] = $r } }
    $vidByDir = @{}
    foreach ($r in $vids.Values) { $d = (PR-Dir $r.old_path).ToLowerInvariant(); if (-not $vidByDir.ContainsKey($d)) { $vidByDir[$d] = New-Object System.Collections.Generic.List[object] }; $vidByDir[$d].Add($r) }
    $sorted = [object[]]@($sidecars | ForEach-Object { [pscustomobject]@{ P = $_; K = [regex]::Split($_.ToLowerInvariant(), '(\d+)') } })
    [Array]::Sort($sorted, [Comparison[object]]{ param($a, $b)
        $n = [math]::Min($a.K.Count, $b.K.Count)
        for ($i = 0; $i -lt $n; $i++) {
            if ($i % 2 -eq 1) { $x = [decimal]$a.K[$i]; $y = [decimal]$b.K[$i]; if ($x -ne $y) { return $x.CompareTo($y) } }
            else { $c = [string]::CompareOrdinal($a.K[$i], $b.K[$i]); if ($c -ne 0) { return $c } }
        }
        return $a.K.Count.CompareTo($b.K.Count) })
    # sidecars left behind in folders with no video come last, so the ones next to (or in Subs under) their video get the plain names first
    $hasVid = { param($q) $dq = (PR-Dir $q).ToLowerInvariant(); if ($vidByDir.ContainsKey($dq)) { return $true }; if ((PR-Base $dq) -eq 'subs') { return $vidByDir.ContainsKey((PR-Dir $dq).ToLowerInvariant()) }; return $false }
    $sorted = [object[]](@($sorted | Where-Object { & $hasVid $_.P }) + @($sorted | Where-Object { -not (& $hasVid $_.P) }))
    $stemLc = @{}; foreach ($r in $vids.Values) { $stemLc[$r.old_path] = (PR-SplitExt (PR-Base $r.old_path))[0].ToLowerInvariant() }   # video name stems, once
    $allMov = $null; $movIdx = $null; $script:PR_TK_CACHE = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $sn = 0
    foreach ($item in $sorted) {
        $sn++; if ($sn % 50 -eq 0) { PR-Progress $sn $sorted.Count 'Matching subtitles' }
        $p = $item.P; $d = PR-Dir $p; $fn = PR-Base $p; $parts = $d.Split('\')
        $row = PR-NewRow $p; $row.media_type = 'sidecar'
        if ($script:PR_DELETE_NFO -and (PR-SplitExt $fn)[1] -ieq '.nfo') {   # Setup: Delete .nfo files during Full Run - not renamed or re-attached
            if (PR-NfoAllowed $p @($MoviesRoot, $SeriesRoot)) { $row.note = 'nfo: delete (sent to the Recycle Bin on Full Run)' } else { $row.note = 'nfo: kept (protected or hidden folder)' }
            $rows.Add($row); continue
        }
        $v = $null; $suffix = $null; $how = ''; $subsUnd = $false; $untagged = $false
        $cands = @(); $fnl = $fn.ToLowerInvariant(); if ($vidByDir.ContainsKey($d.ToLowerInvariant())) { $cands = @(foreach ($cv in $vidByDir[$d.ToLowerInvariant()]) { if ($fnl.StartsWith($stemLc[$cv.old_path], [StringComparison]::Ordinal)) { $cv } }) }
        $last2 = @($parts | Select-Object -Last 2 | ForEach-Object { $_.ToLowerInvariant() })
        if ($cands.Count -gt 0) {
            $bestLen = -1; foreach ($c in $cands) { $L = (PR-SplitExt (PR-Base $c.old_path))[0].Length; if ($L -gt $bestLen) { $bestLen = $L; $v = $c } }
            $suffix = $fn.Substring($bestLen).ToLowerInvariant()
        } elseif ($last2 -contains 'subs') {
            $i = -1; for ($k = $parts.Count - 1; $k -ge 0; $k--) { if ($parts[$k].ToLowerInvariant() -eq 'subs') { $i = $k; break } }
            $parent = ($parts[0..($i - 1)] -join '\').ToLowerInvariant()
            $pv = @(); if ($vidByDir.ContainsKey($parent)) { $pv = $vidByDir[$parent].ToArray() }
            if ($i -eq $parts.Count - 2) {
                $pv = @($pv | Where-Object { (PR-SplitExt (PR-Base $_.old_path))[0].ToLowerInvariant() -eq $parts[-1].ToLowerInvariant() })
                $em = $script:PR_EP.Match($parts[-1])
                if ($pv.Count -eq 0 -and $em.Success) {
                    $code = PR-EpCode $em
                    $pv = @($vids.Values | Where-Object { $_.old_path.ToLowerInvariant().StartsWith($parent + '\', [StringComparison]::Ordinal) -and (PR-EpCodeOf $_.old_path) -eq $code })
                }
            }
            if ($pv.Count -eq 1) {
                $v = $pv[0]; $ls = PR-SubsLang (PR-SplitExt $fn)[0]; $how = 'subs'
                if (-not $ls) { $ls = PR-LangSuffix (PR-SplitExt $fn)[0] }
                if ($ls) { $suffix = $ls + (PR-SplitExt $fn)[1].ToLowerInvariant() } else { $suffix = '.und' + (PR-SplitExt $fn)[1].ToLowerInvariant(); $subsUnd = $true }
            }
        }
        $reattach = ''; $rhigh = $true; $why = ''
        if (-not $v -and -not $row.note) {
            # orphan sidecar (its video was renamed earlier, or it was left behind in an old folder): re-attach it
            $inDir = @(); if ($vidByDir.ContainsKey($d.ToLowerInvariant()) -and $d.TrimEnd('\').ToLowerInvariant() -ne ([string]$mroot).TrimEnd('\').ToLowerInvariant()) {   # never tie a loose file in the library root to another loose video
                $inDir = $vidByDir[$d.ToLowerInvariant()].ToArray() }
            $pick = $null
            $sp = PR-ParseMovie (PR-SidecarStem $fn)
            if ($inDir.Count -eq 1) { $pick = $inDir[0]; $reattach = 'one' }
            elseif ($inDir.Count -gt 1) {
                $tm = PR-TitleMatch $sp $inDir
                if ($tm) { $pick = $tm.V; $reattach = 'title'; $rhigh = $tm.Year; $why = $(if ($tm.Year) { ': same title and year' } else { ': same title, year differs - verify' }) }
            } else {
                # no video here: look for the movie elsewhere (by the sidecar's own name, then by its folder name)
                $fold = $parts[-1]; if ($fold -ieq 'subs' -and $parts.Count -ge 2) { $fold = $parts[-2] }
                if ($null -eq $allMov) { $allMov = @($vids.Values | Where-Object { $_.media_type -eq 'movie' }); $movIdx = PR-TitleIndex $allMov }   # built once per scan
                $tm = $null; if ($sp.Title -and $sp.Year) { $tm = PR-TitleMatch $sp $allMov $movIdx }
                if (-not $tm -and $parts.Count -gt 2) {
                    $fp = PR-ParseMovie $fold
                    if (-not $fp.Year) { $fy = [regex]::Match($fold, '^(.+?)[ ._(\[-]+((?:19|20)\d\d)(?!\d)'); if ($fy.Success) { $fp = PR-ParseMovie ($fy.Groups[1].Value + ' ' + $fy.Groups[2].Value) } }   # 'Superman 2025-1080p x265'
                    $tm = PR-TitleMatch $fp $allMov $movIdx
                }
                if ($tm -and $tm.Year) { $pick = $tm.V; $reattach = 'other'; $rhigh = $false; $why = " in another folder ('" + (PR-Base (PR-Dir $(if ($tm.V.new_path) { $tm.V.new_path } else { $tm.V.old_path }))) + "'): same title and year - verify" }
                elseif ($tm) { $pick = $tm.V; $reattach = 'other'; $rhigh = $false; $why = " in another folder: same title, year differs - verify" }
                else { $row.note = 'sidecar: no video found; left in place' }
            }
            if ($pick) {
                $ext = (PR-SplitExt $fn)[1].ToLowerInvariant()
                $tail = $null
                if ($parts[-1] -ieq 'subs') { $ls = PR-SubsLang (PR-SplitExt $fn)[0]; if ($ls) { $tail = $ls + $ext } }   # Subs\English.srt, Subs\Español (Latinoamérica).spa.srt
                if ($null -eq $tail) { $tail = PR-CleanSpacedTags $fn }
                if ($null -eq $tail) { $tail = PR-SidecarTags $fn }
                if ($null -eq $tail) { $tail = $ext; $untagged = $true }
                $v = $pick; $suffix = $tail; $how = 'reattach'
            }
        }
        if ($v -and $suffix) {
            $base = $v.new_path; if (-not $base) { $base = $v.old_path }
            $np = (PR-SplitExt $base)[0] + $suffix
            $row.tmdb_id = $v.tmdb_id; $row.confidence = $v.confidence; if (-not $row.confidence) { $row.confidence = 'high' }
            if (($reattach -and -not $rhigh) -or $subsUnd) { $row.confidence = 'low' }   # matched by title only / another folder / unknown language: reviewed
            $row.group_key = $v.group_key
            if ($row.confidence -eq 'low' -and $how) { $row.group_key = 'sc|' + $p.ToLowerInvariant() }   # its own Accept tick (the video may already be done)
            $numbered = $false
            if ($how) {
                $bs = (PR-SplitExt $base)[0]; $tg = $suffix.Substring(0, $suffix.Length - (PR-SplitExt ('x' + $suffix))[1].Length); $ex = $suffix.Substring($tg.Length)
                $plain = $bs + $tg + $ex; $pl = $plain.ToLowerInvariant(); $occ = $null
                if ($taken.ContainsKey($pl)) { $occ = [string]$taken[$pl] } elseif ($existing.Contains($pl) -and $pl -ne $p.ToLowerInvariant()) { $occ = $plain }
                if ($occ -and (Test-PRSameSidecar $p $occ)) { $np = $plain }   # an extra copy of what is already there: skipped as a DUPLICATE below
                else { $np = PR-FreeTarget $bs $tg $ex $p $taken $existing; if ($np -cne $plain) { $numbered = $true; $row.confidence = 'low'; $row.group_key = 'sc|' + $p.ToLowerInvariant() } }   # a different track under a new name: reviewed, never automatic
            }
            if ($v.fold_path) { $row.fold_path = PR-Join (PR-Dir $v.fold_path) $fn }   # loose subtitle follows its video into the folder
            if ($taken.ContainsKey($np.ToLowerInvariant()) -or ($existing.Contains($np.ToLowerInvariant()) -and $np.ToLowerInvariant() -ne $p.ToLowerInvariant())) {
                $row.note = 'DUPLICATE sidecar target (same language already placed); left in place'
                # Setup: Recycle duplicate subtitles during Full Run - only subtitles (never .nfo or videos), only inside the roots, never Z:
                if ($script:PR_RECYCLE_DUPSUBS -and (PR-SplitExt $fn)[1] -ine '.nfo' -and (PR-NfoAllowed $p @($MoviesRoot, $SeriesRoot))) {
                    $row.note = 'DUPLICATE sidecar target (same language already placed); will be recycled (Recycle Bin on Full Run; keeps ' + (PR-Base $np) + ')'
                    Add-Member -InputObject $row -NotePropertyName dup_of -NotePropertyValue $np -Force   # the copy that is kept; checked again before recycling
                }
            }
            elseif ($np -ceq $p) { $row.note = 'sidecar already correctly named' }
            else {
                $row.new_path = $np; $taken[$np.ToLowerInvariant()] = $p
                $row.note = 'sidecar of ' + (PR-Base $v.old_path); if (-not $v.new_path) { $row.note += ' (video not moved)' }
                if ($reattach) { $row.note = 'sidecar (re-attached) of ' + (PR-Base $v.old_path) + $(if ($reattach -eq 'one') { ': the only video in this folder' } else { $why }) }
                elseif ($how -eq 'subs') { $row.note = 'sidecar (moved up from Subs) of ' + (PR-Base $v.old_path) + $(if ($subsUnd) { '; language not recognised - verify' } else { '' }) }
                if ($untagged) { $row.note += '; no language tag (kept untagged)' }
                if ($numbered) { $row.note += '; numbered: ' + (PR-Base $plain) + ' already exists with different content - verify' }
            }
        } elseif (-not $row.note) { $row.note = 'sidecar: no matching video; left in place' }
        $rows.Add($row)
    }
    # rows whose only change is a folder's letter case: one row per folder (its video if it has one) carries the folder note and is the one listed
    $caseRep = @{}
    foreach ($pass in 1, 2) { foreach ($r in $rows) { if (Test-PRCaseOnly $r) { $k = (PR-CaseFolderPair $r.old_path $r.new_path)[1].ToLowerInvariant(); if (-not $caseRep.ContainsKey($k) -and ($pass -eq 2 -or $r.media_type -ne 'sidecar')) { $caseRep[$k] = $r } } } }
    foreach ($r in $rows) {
        if (-not (Test-PRCaseOnly $r)) { continue }
        $pr = PR-CaseFolderPair $r.old_path $r.new_path
        if ([object]::ReferenceEquals($caseRep[$pr[1].ToLowerInvariant()], $r)) { $r.case_rep = '1'; $r.note = ("folder renamed: '{0}' -> '{1}'; " -f (PR-Base $pr[0]), (PR-Base $pr[1])) + $r.note }
        elseif ($r.media_type -eq 'sidecar') { $r.note = ([string]$r.note).TrimEnd() + ' (folder case fix)' }
        else { $r.note = 'folder case fix; ' + $r.note }
    }
    foreach ($r in $rows) {   # remembered picks: applied and ticked
        $isPick = $ovHit.ContainsKey($r.old_path)
        if (-not $isPick -and $r.media_type -eq 'episode' -and [string]$r.group_key -like 'show|*') { $sk = ([string]$r.group_key).Substring(5); if ($shows.ContainsKey($sk) -and $shows[$sk] -and $shows[$sk].Pick) { $isPick = $true; if ($r.new_path) { $r.confidence = 'high'; $r.note = 'your pick; ' + $r.note } } }
        if ($isPick -and $r.new_path) { $r.accepted = 'yes' }
    }
    if ($Force.Count) { foreach ($r in $rows) { if ($r.group_key -and $Force.ContainsKey($r.group_key) -and $r.new_path) { $r.accepted = 'yes'; $r.confidence = 'low'; if ($r.media_type -eq 'episode') { $r.note = 'chosen by you; ' + $r.note } }  } }   # a match the user picked counts as accepted
    if ($script:PR_SEASON_FIX -and $sroot) { foreach ($sr in (Get-PRSeasonFolderRows $sroot)) { $rows.Add($sr) } }   # Setup: Standardize season folder names - one row per folder
    PR-Progress 1 1 'Done'
    return ,$rows.ToArray()
}
function PR-EpCode($em) {
    if ($em.Groups[1].Success) { return "$([int]$em.Groups[1].Value)|$([int]$em.Groups[2].Value)" }
    return "$([int]$em.Groups[4].Value)|$([int]$em.Groups[5].Value)"
}
function PR-EpCodeOf([string]$path) { $mm = $script:PR_EP.Match((PR-SplitExt (PR-Base $path))[0]); if ($mm.Success) { return (PR-EpCode $mm) }; return $null }
# trailing language / flag tags of an orphan sidecar name, kept as written: 'X.eng.CC.srt' -> '.eng.CC.srt', 'X.fra.forced.srt' -> '.fra.forced.srt',
# 'X.spa.Latinoamérica.srt' -> '.spa.Latinoamérica.srt'; .nfo -> '.nfo'. $null when a subtitle has no language tag.
function PR-SidecarTags([string]$fn) {
    $se = PR-SplitExt $fn; $ext = $se[1].ToLowerInvariant()
    if ($ext -eq '.nfo') { return '.nfo' }
    $seg = $se[0].Split('.'); $flags = @('sdh', 'hi', 'cc', 'forced', 'default', 'hearing', 'impaired')
    $isLang = { param($w) $l = $w.ToLowerInvariant(); $script:PR_LANG.ContainsKey($l) -or ($script:PR_LANG.Values -contains $l) -or ($w -cmatch '^[a-z]{2,3}$') }   # known language, or a short lowercase code (hin, tam)
    $keep = New-Object System.Collections.Generic.List[string]; $hasLang = $false
    for ($i = $seg.Count - 1; $i -ge 1; $i--) {
        $w = $seg[$i]
        if ($flags -contains $w.ToLowerInvariant()) { $keep.Insert(0, $w); continue }
        if (& $isLang $w) { $keep.Insert(0, $w); $hasLang = $true; continue }
        if ($w -cmatch '^\p{Lu}\p{L}{1,19}$' -and $i -ge 2 -and (& $isLang $seg[$i - 1])) { $keep.Insert(0, $w); continue }   # region after a language: fra.Canada, spa.Latinoamérica
        break
    }
    if (-not $hasLang) { return $null }
    return '.' + ($keep -join '.') + $ext
}
function PR-SidecarStem([string]$fn) { $t = PR-SidecarTags $fn; $s = (PR-SplitExt $fn)[0]; if ($t -and $t -ne '.nfo') { $n = $t.Length - (PR-SplitExt $fn)[1].Length; if ($n -gt 0 -and $s.Length -gt $n) { $s = $s.Substring(0, $s.Length - $n) } }; return $s }
# title + year match of a parsed name against videos (Part II = Part 2); returns @{V; Year} for exactly one title match, preferring the one whose year matches
function PR-TitleKey([string]$t) {
    $rm = @{ i = '1'; ii = '2'; iii = '3'; iv = '4'; v = '5'; vi = '6'; vii = '7'; viii = '8'; ix = '9'; x = '10' }
    $w = @((PR-Norm $t).Split(' ') | Where-Object { $_ -and $_ -ne 'part' } | ForEach-Object { if ($rm.ContainsKey($_)) { $rm[$_] } else { $_ } })
    return ($w -join ' ')
}
$script:PR_TK_CACHE = New-Object 'System.Collections.Generic.Dictionary[string,object]'
function PR-TitleKeyOf($x) {
    # title key and year of a video's (new or old) name, parsed once per name
    $vb = $x.new_path; if (-not $vb) { $vb = $x.old_path }
    $c = $null; if ($script:PR_TK_CACHE.TryGetValue($vb, [ref]$c)) { return $c }
    $vp = PR-ParseMovie (PR-SplitExt (PR-Base $vb))[0]; $kk = ''; if ($vp.Title) { $kk = PR-TitleKey $vp.Title }
    $c = [pscustomobject]@{ K = $kk; Y = $vp.Year }; $script:PR_TK_CACHE[$vb] = $c; return $c
}
function PR-TitleIndex($videos) {
    $ix = @{}; foreach ($x in $videos) { $tk = PR-TitleKeyOf $x; if (-not $tk.K) { continue }; if (-not $ix.ContainsKey($tk.K)) { $ix[$tk.K] = New-Object System.Collections.Generic.List[object] }; $ix[$tk.K].Add([pscustomobject]@{ V = $x; Y = $tk.Y }) }
    return $ix
}
function PR-TitleMatch($sp, $videos, $Index = $null) {
    if (-not $sp -or -not $sp.Title) { return $null }
    $k = PR-TitleKey $sp.Title; if (-not $k) { return $null }
    $hits = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Index) { if ($Index.ContainsKey($k)) { foreach ($h in $Index[$k]) { $hits.Add($h) } } }   # prebuilt title index (same hits, same order)
    else { foreach ($x in $videos) { $tk = PR-TitleKeyOf $x; if ($tk.K -and $tk.K -eq $k) { $hits.Add([pscustomobject]@{ V = $x; Y = $tk.Y }) } } }
    $yh = @($hits | Where-Object { $sp.Year -and $_.Y -and [int]$_.Y -eq [int]$sp.Year })
    if ($yh.Count -eq 1) { return @{ V = $yh[0].V; Year = $true } }
    if ($yh.Count -eq 0 -and $hits.Count -eq 1) { return @{ V = $hits[0].V; Year = $false } }
    return $null
}
# language from a free-form name: 'English', '3_English', 'Español (Latinoamérica)', 'français (Canada)', 'eng CC', 'Forced' ...
# returns '.en', '.es-419', '.fr-CA', '.en.sdh', '.en.forced' (same 2-letter codes as the rest of Renamr), or $null
$script:PR_NATIVE = @{ 'español' = 'es'; 'espanol' = 'es'; 'castellano' = 'es'; 'français' = 'fr'; 'francais' = 'fr'; 'deutsch' = 'de'; 'português' = 'pt'; 'portugues' = 'pt';
  'italiano' = 'it'; 'nederlands' = 'nl'; 'polski' = 'pl'; 'svenska' = 'sv'; 'norsk' = 'no'; 'dansk' = 'da'; 'suomi' = 'fi'; 'türkçe' = 'tr'; 'magyar' = 'hu';
  'čeština' = 'cs'; 'русский' = 'ru'; 'ελληνικά' = 'el'; 'עברית' = 'he'; 'العربية' = 'ar'; '日本語' = 'ja'; '中文' = 'zh'; '한국어' = 'ko' }
$script:PR_REGION = @{ 'latinoamérica' = '419'; 'latinoamerica' = '419'; 'latino' = '419'; 'latam' = '419'; 'latin' = '419'; 'canada' = 'CA'; 'canadien' = 'CA'; 'québec' = 'CA'; 'quebec' = 'CA';
  'portugal' = 'PT'; 'brasil' = 'BR'; 'brazil' = 'BR'; 'brasileiro' = 'BR'; 'españa' = 'ES'; 'spain' = 'ES'; 'castilian' = 'ES'; 'european' = 'ES' }
function PR-SubsLang([string]$name) {
    $words = @([regex]::Matches($name.ToLowerInvariant(), '\p{L}+') | ForEach-Object { $_.Value })
    $code = $null; foreach ($w in $words) { if ($script:PR_LANG.ContainsKey($w)) { $code = $script:PR_LANG[$w]; break }; if ($script:PR_NATIVE.ContainsKey($w)) { $code = $script:PR_NATIVE[$w]; break } }
    if (-not $code) { return $null }
    if ($code -notmatch '-') { foreach ($w in $words) { if ($script:PR_REGION.ContainsKey($w)) { $rg = $script:PR_REGION[$w]; if ($rg -eq '419' -and $code -ne 'es') { continue }; if ($rg -eq 'CA' -and $code -ne 'fr' -and $code -ne 'en') { continue }; if (($rg -eq 'PT' -or $rg -eq 'BR') -and $code -ne 'pt') { continue }; if ($rg -eq 'ES' -and $code -ne 'es') { continue }; $code = $code + '-' + $rg; break } } }
    $flags = @(); if ($words -contains 'forced') { $flags += 'forced' }
    if ($words -contains 'sdh' -or $words -contains 'cc' -or ($words -contains 'hi') -or ($words -contains 'hearing')) { $flags += 'sdh' }
    return '.' + ((@($code) + $flags) -join '.')
}
# tag block written with spaces between tokens ('X.eng.CC eng.srt', 'X.fra.Canada fre.srt'): a clean tag ('.en.sdh.srt', '.fr-CA.srt'); $null when the block has no space
function PR-CleanSpacedTags([string]$fn) {
    $se = PR-SplitExt $fn; $ext = $se[1].ToLowerInvariant(); if ($ext -eq '.nfo') { return $null }
    $seg = $se[0].Split('.'); $flags = @('sdh', 'hi', 'cc', 'forced', 'default', 'hearing', 'impaired')
    $ok = { param($t) $l = $t.ToLowerInvariant(); ($flags -contains $l) -or $script:PR_LANG.ContainsKey($l) -or ($script:PR_LANG.Values -contains $l) -or $script:PR_NATIVE.ContainsKey($l) -or $script:PR_REGION.ContainsKey($l) }
    $blk = New-Object System.Collections.Generic.List[string]; $spaced = $false
    for ($i = $seg.Count - 1; $i -ge 1; $i--) {
        $tk = @($seg[$i].Split(' ') | Where-Object { $_ }); if ($tk.Count -eq 0) { break }
        $all = $true; foreach ($t in $tk) { if (-not (& $ok $t)) { $all = $false; break } }
        if (-not $all) { break }
        if ($tk.Count -gt 1) { $spaced = $true }; $blk.Insert(0, ($tk -join ' '))
    }
    if (-not $spaced) { return $null }
    $t = PR-SubsLang ($blk -join ' '); if (-not $t) { return $null }
    return $t + $ext
}
# first free name: base+tag+ext, then (untagged) base.und+ext, then base+tag.2+ext, .3 ... never an existing or already planned file
# is sidecar $a just another copy of $b? .nfo: always (one .nfo per video); subtitles: identical bytes, or sizes within 3% (same language and flags, since the names match)
function Test-PRSameSidecar([string]$a, [string]$b) {
    if ((PR-SplitExt $a)[1] -ieq '.nfo') { return $true }
    try { $fa = Get-Item -LiteralPath $a -ErrorAction Stop; $fb = Get-Item -LiteralPath $b -ErrorAction Stop } catch { return $false }
    if ($fa.Length -eq $fb.Length -and (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash) { return $true }
    $big = [math]::Max($fa.Length, $fb.Length); if ($big -eq 0) { return $true }
    return ([math]::Abs($fa.Length - $fb.Length) / $big) -le 0.03
}
function PR-FreeTarget([string]$bs, [string]$tg, [string]$ex, [string]$self, $taken, $existing) {
    $free = { param($c) $l = $c.ToLowerInvariant(); -not $taken.ContainsKey($l) -and (-not $existing.Contains($l) -or $l -eq $self.ToLowerInvariant()) }
    $c = $bs + $tg + $ex; if (& $free $c) { return $c }
    if (-not $tg -and $ex -ne '.nfo') { $tg = '.und'; $c = $bs + $tg + $ex; if (& $free $c) { return $c } }
    for ($n = 2; $n -lt 100; $n++) { $c = $bs + $tg + '.' + $n + $ex; if (& $free $c) { return $c } }
    return $bs + $tg + $ex
}
function PR-LangSuffix([string]$name) {
    $words = @([regex]::Matches($name.ToLowerInvariant(), '[a-z]+') | ForEach-Object { $_.Value })
    $code = $null; foreach ($w in $words) { if ($script:PR_LANG.ContainsKey($w)) { $code = $script:PR_LANG[$w]; break } }
    if (-not $code) { return $null }
    $flags = @(); foreach ($f in 'forced', 'sdh') { if ($words -contains $f) { $flags += $f } }
    if ($words -contains 'hi' -and -not ($words -contains 'sdh')) { $flags += 'sdh' }
    return '.' + ((@($code) + $flags) -join '.')
}
# one line that explains the 'Unmatched / left in place' view
function Get-PRUnmatchedLine($rows) {
    $m = 0; $e = 0; $eNoSeries = 0; $s = 0
    foreach ($r in $rows) {
        if ($r.new_path -or $r.fold_path) { continue }
        $n = [string]$r.note
        if ($r.media_type -eq 'sidecar') { if ($n -like 'sidecar: *') { $s++ } }
        elseif ($n.StartsWith('unmatched')) { if ($r.media_type -eq 'episode') { $e++; if ($n -like '*no Series folder selected*') { $eNoSeries++ } } else { $m++ } }
    }
    $line = "Unmatched: $m movie(s), $e episode(s), $s sidecar(s) with no video."
    if ($eNoSeries) { $line += " $eNoSeries episode(s) are in the Movies folder but no Series folder is set: choose a Series folder to rename them (they are not moved now)." }
    return $line
}
function Get-PRSummary($rows) {
    $t = 0; $h = 0; $s = 0; $a = 0; $rc = Get-PRReviewCounts $rows; $cf = @{}
    $sfn = @($rows | Where-Object { (Test-PRSeasonRow $_) -and $_.new_path }).Count
    foreach ($r in $rows) {
        if (Test-PRSeasonRow $r) { continue }
        $t++
        if (Test-PRCaseOnly $r) { $cf[(PR-CaseFolderPair $r.old_path $r.new_path)[1].ToLowerInvariant()] = 1 }
        elseif ($r.new_path) { if ($r.confidence -eq 'high') { $h++ } } else { $s++ }
        if ($r.note -like '*already correctly named*') { $a++ }
    }
    return "Result: $h ready to rename (high confidence), $($cf.Count) folder name(s) to fix (letter case), $(if ($sfn) { "$sfn season folder(s) to standardize, " })$($rc.Total) movie(s)/show(s) to review ($($rc.Low) low-confidence matches, $($rc.NoMatch) with no match), $s file(s) left as they are (unmatched or no change needed; $a already correctly named), $t total."
}

# ---------- file system scan ----------
# ---------- parallel prefetch of online lookups (first scan with an empty cache) ----------
# The scan itself is unchanged: it asks the same questions in the same order. Before it runs, the same matching code is
# dry-run per movie / show with the cache in 'collect' mode: the first request not in the cache is noted and that lookup stops.
# The noted requests are fetched by a pool of workers at the same overall rate, stored in the cache, and the dry run is
# repeated until nothing new is needed. The real scan then finds every answer in the cache, so its results are identical.
function Invoke-PRFetchBatch($db, $Reqs, [int]$Workers = 8) {
    $code = $script:PR_ENGINE_CODE; $list = @($Reqs)
    if (-not $code -or $list.Count -lt 4 -or $Workers -le 1) {   # few requests (or no engine text): fetch here, one by one
        foreach ($q in $list) { try { if ($q.Provider -eq 'tvdb') { [void](PR-TvdbGet $db $q.Path $q.Params) } else { [void](PR-TmdbGet $db $q.Path $q.Params) } } catch { PR-Log "Lookup failed: $($q.Path) $($_.Exception.Message)" } }
        return
    }
    $tok = ''; if (@($list | Where-Object { $_.Provider -eq 'tvdb' }).Count -and $db.Tvdb.Key) { try { $tok = PR-TvdbToken $db } catch { PR-Log "TVDB login failed: $($_.Exception.Message)" } }
    $n = [math]::Min($Workers, $list.Count)
    $pool = [runspacefactory]::CreateRunspacePool(1, $n); $pool.Open()
    $job = {
        param($code, $cfg, $batch)
        . ([scriptblock]::Create($code))
        $d = New-PRTmdb -Key $cfg.Key -CachePath '' -TvdbKey $cfg.TvdbKey -TvdbPin $cfg.TvdbPin -Source $cfg.Source -UsTitles $cfg.UsTitles
        $d.GapMs = $cfg.GapMs; $d.TmdbBase = $cfg.TmdbBase; if ($cfg.Token) { $d.Tvdb.Token = $cfg.Token }
        $err = New-Object System.Collections.Generic.List[string]
        foreach ($q in $batch) { try { if ($q.Provider -eq 'tvdb') { [void](PR-TvdbGet $d $q.Path $q.Params) } else { [void](PR-TmdbGet $d $q.Path $q.Params) } } catch { $err.Add("$($q.Path): $($_.Exception.Message)") } }
        $out = New-Object System.Collections.Generic.List[object]; foreach ($kv in $d.Cache.GetEnumerator()) { $out.Add([pscustomobject]@{ K = $kv.Key; V = $kv.Value }) }
        return [pscustomobject]@{ Entries = $out.ToArray(); Calls = $d.Calls; Errors = $err.ToArray() }
    }
    # each worker keeps its own gap, so together they stay at the single-worker rate x ~1.3 (TMDB allows ~40 requests/s; 429 is retried)
    $cfg = @{ Key = $db.Key; TvdbKey = $db.Tvdb.Key; TvdbPin = $db.Tvdb.Pin; Source = $db.Source; UsTitles = [bool]$db.UsTitles; GapMs = [int]([math]::Ceiling(25 * $n)); TmdbBase = $db.TmdbBase; Token = $tok }
    $chunks = @(); for ($i = 0; $i -lt $n; $i++) { $chunks += , (New-Object System.Collections.Generic.List[object]) }
    for ($i = 0; $i -lt $list.Count; $i++) { $chunks[$i % $n].Add($list[$i]) }
    $hs = @(); foreach ($c in $chunks) { $ps = [powershell]::Create(); $ps.RunspacePool = $pool; [void]$ps.AddScript($job.ToString()).AddArgument($code).AddArgument($cfg).AddArgument($c.ToArray()); $hs += @{ PS = $ps; H = $ps.BeginInvoke() } }
    try {
        foreach ($h in $hs) {
            while (-not $h.H.IsCompleted) { if (PR-Cancelled) { foreach ($x in $hs) { try { $x.PS.Stop() } catch { } }; throw 'Cancelled' }; Start-Sleep -Milliseconds 50 }
            foreach ($r in @($h.PS.EndInvoke($h.H))) { if (-not $r) { continue }; foreach ($e in @($r.Entries)) { if ($e -and -not $db.Cache.ContainsKey($e.K)) { $db.Cache[$e.K] = $e.V; $db.Dirty++ } }; $db.Calls += [int]$r.Calls; foreach ($m in @($r.Errors)) { PR-Log "Lookup failed: $m" } }
        }
    } finally { foreach ($h in $hs) { $h.PS.Dispose() }; $pool.Close(); $pool.Dispose() }
}
function Invoke-PRPrefetch($db, [string[]]$Paths, [string]$MoviesRoot, [string]$SeriesRoot, [int]$Workers = 8) {
    $mroot = ([string]$MoviesRoot).TrimEnd('\'); $sroot = ([string]$SeriesRoot).TrimEnd('\')
    $movies = @{}; $shows = @{}
    $vids = @($Paths | Where-Object { $_ -and -not $script:PR_SKIP.IsMatch($_) -and $script:PR_VIDEO -contains (PR-SplitExt $_)[1].ToLowerInvariant() })
    $ident = Get-PRShowIdentity $vids $sroot
    foreach ($p in $Paths) {
        if (-not $p -or $script:PR_SKIP.IsMatch($p)) { continue }
        $e = (PR-SplitExt $p)[1].ToLowerInvariant(); if ($script:PR_VIDEO -notcontains $e) { continue }
        $stem = (PR-SplitExt (PR-Base $p))[0]; $m = $script:PR_EP.Match($stem)
        if ($m.Success -and $sroot) {
            $c = PR-ParseShow $stem.Substring(0, $m.Index); $idn = $ident[$p.ToLowerInvariant()]
            if ($idn) { $c = @{ Title = $idn.Title; Year = $idn.Year } }
            if (-not $c.Title) { continue }
            $sn = $(if ($m.Groups[1].Success) { [int]$m.Groups[1].Value } else { [int]$m.Groups[4].Value })
            $k = (PR-Norm $c.Title) + '|' + $c.Year; if (-not $shows.ContainsKey($k)) { $shows[$k] = @{ T = $c.Title; Y = $c.Year; S = @{}; E = $(if ($idn) { $idn.Eps } else { $null }) } }; $shows[$k].S[$sn] = 1
        } elseif ($mroot -and (PR-Under $p $mroot)) {
            $pm = PR-ParseMovie $stem
            if (-not $pm.Year -and $pm.Title) { $pd = PR-Dir $p; if ($pd.TrimEnd('\').ToLowerInvariant() -ne $mroot.ToLowerInvariant()) { $fp = PR-ParseMovie (PR-Base $pd); if ($fp.Year -and $fp.Title -and (PR-Sim $fp.Title $pm.Title) -ge 0.7) { $pm = @{ Title = $pm.Title; Year = $fp.Year } } } }
            if ($pm.Title) { $movies["$($pm.Title)|$($pm.Year)"] = @{ T = $pm.Title; Y = $pm.Year } }
        }
    }
    $units = New-Object System.Collections.Generic.List[object]
    foreach ($v in $movies.Values) { $units.Add(@{ K = 'm'; T = $v.T; Y = $v.Y }) }
    foreach ($v in $shows.Values) { $units.Add(@{ K = 's'; T = $v.T; Y = $v.Y; S = @($v.S.Keys); E = $v.E }) }
    $total = 0
    for ($wave = 1; $wave -le 8 -and $units.Count; $wave++) {
        if (PR-Cancelled) { throw 'Cancelled' }
        PR-Progress $wave 8 "Looking up online (round $wave, $($units.Count) titles)"
        $db.Collect = @{}; $next = New-Object System.Collections.Generic.List[object]
        try {
            foreach ($u in $units) {
                $pending = $false
                try {
                    if ($u.K -eq 'm') { [void](PR-MatchMovie $db $u.T $u.Y) }
                    else {
                        $seen = @{}; $sh = PR-MatchShowChecked $db $seen $u.T $u.Y $u.E
                        if ($sh) { foreach ($sn in $u.S) { try { [void](PR-Season $db $seen $sh.Id ([int]$sn) $sh.Provider) } catch { if ($_.Exception.Message -eq 'PRCollect') { $pending = $true } else { throw } } } }
                    }
                } catch { if ($_.Exception.Message -eq 'PRCollect') { $pending = $true } }   # other errors: the real scan reports them
                if ($pending) { $next.Add($u) }
            }
        } finally { $reqs = @($db.Collect.Values); $db.Collect = $null }
        if ($reqs.Count -eq 0) { break }
        $total += $reqs.Count
        Invoke-PRFetchBatch $db $reqs $Workers
        $units = $next
    }
    if ($db.Dirty) { Save-PRTmdbCache $db }
    return $total
}
function Get-PRFiles([string[]]$Roots) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($root in $Roots) {
        if (-not $root) { continue }
        if (-not [IO.Directory]::Exists($root)) { PR-Log "Folder not found: $root"; continue }
        $stack = New-Object System.Collections.Generic.Stack[string]; $stack.Push($root)
        while ($stack.Count -gt 0) {
            if (PR-Cancelled) { throw 'Cancelled' }
            $d = $stack.Pop()
            try { foreach ($f in [IO.Directory]::GetFiles($d)) { $out.Add($f) } } catch { PR-Log "Cannot read $d : $($_.Exception.Message)" }
            try { foreach ($sd in [IO.Directory]::GetDirectories($d)) { $stack.Push($sd) } } catch {}
            if ($script:PRSync) { $script:PRSync.Phase = "Scanning ($($out.Count) files)" }
        }
    }
    return ,$out.ToArray()
}

# ---------- CSV helpers (UTF-8 with BOM, same columns as plan.py) ----------
function PR-CsvField($v) { $s = [string]$v; if ($s -match '[",\r\n]') { return '"' + $s.Replace('"', '""') + '"' }; return $s }
function Export-PRCsv($rows, [string]$path, [string[]]$columns) {
    $sw = New-Object IO.StreamWriter($path, $false, (New-Object Text.UTF8Encoding($true)))
    try {
        $sw.Write(($columns -join ',') + "`r`n")
        foreach ($r in $rows) { $sw.Write((($columns | ForEach-Object { PR-CsvField $r.$_ }) -join ',') + "`r`n") }
    } finally { $sw.Close() }
}
function Add-PRCsvRows($rows, [string]$path, [string[]]$columns, [ref]$Written) {
    # appends only the rows not yet written (header first time), so the undo log grows in place instead of being rewritten after every move
    if ($Written.Value -ge $rows.Count) { return }
    $new = ($Written.Value -eq 0)
    $sw = New-Object IO.StreamWriter($path, (-not $new), (New-Object Text.UTF8Encoding($new)))
    try {
        if ($new) { $sw.Write(($columns -join ',') + "`r`n") }
        for ($i = $Written.Value; $i -lt $rows.Count; $i++) { $r = $rows[$i]; $f = foreach ($c in $columns) { PR-CsvField $r.$c }; $sw.Write(($f -join ',') + "`r`n") }
        $sw.Flush()
    } finally { $sw.Close() }
    $Written.Value = $rows.Count
}
function Export-PRPlan($rows, [string]$path) { Export-PRCsv $rows $path @('old_path','new_path','media_type','tmdb_id','confidence','note','fold_path','accepted','group_key') }
# where a Full Run puts a row: the planned rename, or for a loose movie whose rename is not applied, just its own folder (name kept)
# Setup option "Full Run applies only ticked rows": off = high-confidence + accepted + folder-only moves (default); on = only rows ticked Accept
$script:PR_ONLY_TICKED = $false
function PR-ApplyTarget($r, [bool]$HighOnly) {
    if (Test-PRSkipped $r) { return '' }   # unticked in the grid: this file is left alone
    if ($script:PR_ONLY_TICKED) {
        if (-not ($r.PSObject.Properties['accepted'] -and $r.accepted -eq 'yes')) { return '' }
        if ($r.new_path) { return [string]$r.new_path }
        if ($r.PSObject.Properties['fold_path'] -and $r.fold_path) { return [string]$r.fold_path }
        return ''
    }
    if ($r.new_path -and (-not $HighOnly -or $r.confidence -eq 'high' -or ($r.PSObject.Properties['accepted'] -and $r.accepted -eq 'yes'))) { return [string]$r.new_path }
    if ($r.PSObject.Properties['fold_path'] -and $r.fold_path) { return [string]$r.fold_path }
    return ''
}
# counts for the Full Run confirmation: High = renamed as high confidence (or everything when not high-only), Accepted = low ones you accepted, Folder = only put into their own folder
# a row whose only change is the letter case of a folder (the file name itself is already right)
# ---------- what Full Run will do with a row (the grid's Accept box shows exactly this) ----------
# skip = 'yes': the user unticked a row Full Run would otherwise act on (that file / folder only, or a movie / show with its subtitles)
function Test-PRSkipped($r) { return ($r.PSObject.Properties['skip'] -and [string]$r.skip -eq 'yes') }
function Get-PRActKind($r) {
    # 'nfo' / 'dupsub' / 'season' rows are acted on by their Setup option; 'auto' = renamed without a tick; 'accept' = needs a tick; '' = nothing to do
    $n = [string]$r.note
    if ($n.StartsWith('nfo: delete')) { return 'nfo' }
    if (Test-PRDupSubRow $r) { return 'dupsub' }
    if (Test-PRSeasonRow $r) { if ($r.new_path) { return 'season' }; return '' }
    if (-not ($r.new_path -or ($r.PSObject.Properties['fold_path'] -and $r.fold_path))) { return '' }
    if ($r.new_path -and $r.confidence -ne 'high') { return 'accept' }
    return 'auto'
}
function Get-PROptionOff($r) {
    # the Setup option a row depends on, when it is off ('' when not)
    switch (Get-PRActKind $r) { 'nfo' { if (-not $script:PR_DELETE_NFO) { return 'Delete .nfo files' } } 'dupsub' { if (-not $script:PR_RECYCLE_DUPSUBS) { return 'Recycle duplicate subtitles' } } 'season' { if (-not $script:PR_SEASON_FIX) { return 'Standardize season folder names' } } }
    return ''
}
function Test-PRWillAct($r, [bool]$HighOnly = $true) {
    # $true when the next Full Run will rename / move / recycle this row
    $k = Get-PRActKind $r; if (-not $k -or (Test-PRSkipped $r)) { return $false }
    if (Get-PROptionOff $r) { return $false }
    if ($script:PR_ONLY_TICKED -and $k -ne 'nfo' -and $k -ne 'dupsub') { return ($r.PSObject.Properties['accepted'] -and $r.accepted -eq 'yes') }
    if ($k -eq 'accept') { return (-not $HighOnly) -or ($r.PSObject.Properties['accepted'] -and $r.accepted -eq 'yes') }
    return $true
}
function Get-PRRowState($r, [bool]$HighOnly = $true) {
    # the four answers above in one pass (for the grid: thousands of rows): @(act kind, option off, will act, skipped)
    # must give exactly what Get-PRActKind, Get-PROptionOff, Test-PRWillAct and Test-PRSkipped give (tests\Test-RowState.ps1)
    $n = [string]$r.note; $pp = $r.PSObject.Properties
    $sk = [bool]($pp['skip'] -and [string]$r.skip -eq 'yes')
    if ($n.StartsWith('nfo: delete')) { $k = 'nfo' }
    elseif ($n.StartsWith('DUPLICATE sidecar target') -and $n.Contains('will be recycled') -and $pp['dup_of'] -and [string]$r.dup_of) { $k = 'dupsub' }
    elseif ($r.media_type -eq 'season folder') { $k = $(if ($r.new_path) { 'season' } else { '' }) }
    elseif (-not ($r.new_path -or ($pp['fold_path'] -and $r.fold_path))) { $k = '' }
    elseif ($r.new_path -and $r.confidence -ne 'high') { $k = 'accept' }
    else { $k = 'auto' }
    $off = ''
    if ($k -eq 'nfo') { if (-not $script:PR_DELETE_NFO) { $off = 'Delete .nfo files' } }
    elseif ($k -eq 'dupsub') { if (-not $script:PR_RECYCLE_DUPSUBS) { $off = 'Recycle duplicate subtitles' } }
    elseif ($k -eq 'season') { if (-not $script:PR_SEASON_FIX) { $off = 'Standardize season folder names' } }
    $acc = [bool]($pp['accepted'] -and $r.accepted -eq 'yes')
    if (-not $k -or $sk -or $off) { $w = $false }
    elseif ($script:PR_ONLY_TICKED -and $k -ne 'nfo' -and $k -ne 'dupsub') { $w = $acc }
    elseif ($k -eq 'accept') { $w = (-not $HighOnly) -or $acc }
    else { $w = $true }
    return @($k, $off, $w, $sk)
}
function Set-PRRowAct($Rows, $Row, [bool]$On, [bool]$HighOnly = $true) {
    # tick / untick one row as the grid shows it. Option rows (nfo, duplicate subtitle, season folder) and loose files: that row only.
    # A movie / show: the whole group (its subtitles follow, so names stay consistent). Returns the number of rows changed.
    $k = Get-PRActKind $Row; if (-not $k) { return 0 }
    $set = @($Row)
    if (($k -eq 'auto' -or $k -eq 'accept') -and $Row.group_key) { $set = @(foreach ($x in $Rows) { if ($x.group_key -eq $Row.group_key -and (Get-PRActKind $x) -in 'auto', 'accept') { $x } }) }
    foreach ($r in $set) {
        if (-not $r.PSObject.Properties['skip']) { Add-Member -InputObject $r -NotePropertyName skip -NotePropertyValue '' -Force }
        if ($On) { $r.skip = ''; if ((Get-PRActKind $r) -eq 'accept' -or $script:PR_ONLY_TICKED) { $r.accepted = 'yes' } }
        else { $r.skip = 'yes'; if ($r.PSObject.Properties['accepted']) { $r.accepted = '' } }
    }
    return $set.Count
}
function Test-PRCaseOnly($r) { $o = [string]$r.old_path; $n = [string]$r.new_path; return ([bool]$n -and $o -ieq $n -and $o -cne $n -and (PR-Base $o) -ceq (PR-Base $n)) }
function PR-CaseFolderPair([string]$o, [string]$n) {
    # first folder whose case differs: returns @(old full folder, new full folder)
    $a = $o.Split([char]92); $b = $n.Split([char]92)
    for ($i = 0; $i -lt [math]::Min($a.Count, $b.Count) - 1; $i++) { if ($a[$i] -cne $b[$i]) { return @((($a[0..$i]) -join '\'), (($b[0..$i]) -join '\')) } }
    return @((PR-Dir $o), (PR-Dir $n))
}
function Get-PRRunCounts($Rows, [bool]$HighOnly) {
    # High / Accepted / Folder count files; CaseFolders counts folders (one per folder, not per file); Total = files that really move
    $c = @{ High = 0; Accepted = 0; Folder = 0; Total = 0; CaseFolders = 0; SeasonFolders = 0 }; $cf = @{}
    $sf = @{}; foreach ($r in $Rows) { if ((Test-PRSeasonRow $r) -and $r.new_path) { $sf[([string]$r.new_path).ToLowerInvariant()] = 1 } }
    foreach ($r in $Rows) {
        if (Test-PRSeasonRow $r) { if ($r.new_path -and -not (Test-PRSkipped $r) -and (-not $script:PR_ONLY_TICKED -or $r.accepted -eq 'yes')) { $c.SeasonFolders++ }; continue }
        $t = PR-ApplyTarget $r $HighOnly; if (-not $t) { continue }
        if ($t -ceq [string]$r.new_path -and (Test-PRCaseOnly $r) -and $sf.ContainsKey((PR-CaseFolderPair $r.old_path $r.new_path)[1].ToLowerInvariant())) { continue }   # covered by the season folder rename
        if ($t -ceq [string]$r.new_path -and (Test-PRCaseOnly $r)) { $cf[(PR-CaseFolderPair $r.old_path $r.new_path)[1].ToLowerInvariant()] = 1; continue }
        $c.Total++
        if ($t -cne [string]$r.new_path) { $c.Folder++ } elseif ((-not $HighOnly -and -not $script:PR_ONLY_TICKED) -or $r.confidence -eq 'high') { $c.High++ } else { $c.Accepted++ }
    }
    $c.CaseFolders = $cf.Count
    return $c
}
# rows the user can review: a low-confidence match with a rename still pending, or a movie/show that found no match
# (already-named files, duplicates and clashes have nothing pending, so they are not listed)
function Test-PRReviewable($r) { return ([bool]$r.group_key -and $r.media_type -ne 'sidecar' -and $r.confidence -ne 'high' -and ([bool]$r.new_path -or ([string]$r.note).StartsWith('unmatched'))) }
# review counts per movie/show (a show counts once): Low = low-confidence matches, NoMatch = no match found
function Get-PRReviewCounts($Rows) {
    $low = @{}; $none = @{}
    foreach ($r in $Rows) { if (Test-PRReviewable $r) { if ($r.new_path) { $low[$r.group_key] = 1 } else { $none[$r.group_key] = 1 } } }
    foreach ($k in @($low.Keys)) { $none.Remove($k) }
    return @{ Low = $low.Count; NoMatch = $none.Count; Total = $low.Count + $none.Count }
}
# tick or untick Accept for a whole group (a movie with its subtitles, or every episode of a show)
# rows whose Accept box can be ticked: every movie/episode row with a pending change (high, low, folder case, folder-only).
# By default a ticked high or folder-case row is only a visible approval (they are applied anyway); a ticked low row gets its full rename.
function Test-PRTickable($r) { return ([bool]$r.group_key -and ($r.media_type -ne 'sidecar' -or ([string]$r.group_key).StartsWith('sc|')) -and ([bool]$r.new_path -or ($r.PSObject.Properties['fold_path'] -and [bool]$r.fold_path))) }
function Set-PRAccepted($Rows, [string]$GroupKey, [bool]$On) {
    $n = 0; foreach ($r in $Rows) { if ($r.group_key -eq $GroupKey -and ($r.new_path -or ($r.PSObject.Properties['fold_path'] -and $r.fold_path))) { $r.accepted = $(if ($On) { 'yes' } else { '' }); $n++ } }; return $n
}
# Accept all / Clear accepts for a set of groups (e.g. what the current filter shows); unmatched groups cannot be accepted
function Set-PRAcceptedBulk($Rows, [string[]]$GroupKeys, [bool]$On) {
    $res = @{ Accepted = 0; Skipped = 0 }; $seen = @{}
    foreach ($k in $GroupKeys) {
        if (-not $k -or $seen.ContainsKey($k)) { continue }; $seen[$k] = 1
        $ok = $false; foreach ($r in $Rows) { if ($r.group_key -eq $k -and (Test-PRTickable $r)) { $ok = $true; break } }
        if (-not $ok) { if ($On) { $res.Skipped++ }; continue }
        [void](Set-PRAccepted $Rows $k $On); $res.Accepted++
    }
    return $res
}
# match candidates for a title (already-cached searches cost nothing): newest best first, by name similarity
function Get-PRCandidates($Db, [string]$Kind, [string]$Title, $Year) {
    $out = New-Object System.Collections.Generic.List[object]; $seen = @{}
    if (-not $Title) { return }
    $path = '/search/movie'; if ($Kind -eq 'show') { $path = '/search/tv' }
    $idm = [regex]::Match($Title, '^\s*(?i:(tmdb|tvdb)\s*[:#]?)?\s*(\d+)\s*$')
    if ($idm.Success) { $c = Get-PRById $Db $Kind $(if ($idm.Groups[1].Success) { $idm.Groups[1].Value.ToLowerInvariant() } else { 'tmdb' }) $idm.Groups[2].Value; if ($c) { return @($c) }; return @() }   # '136418', 'tmdb:136418', 'tvdb:1884'
    $ys = @($null); if ($Year) { $ys = @([int]$Year, $null) }
    foreach ($pv in (PR-Providers $Db $(if ($Kind -eq 'show') { 'tv' } else { 'movie' }))) {
        foreach ($y in $ys) {
            $q = @{ query = $Title }
            if ($Kind -eq 'show') { $q.first_air_date_year = $y } else { $q.primary_release_year = $y; $q.include_adult = 'false' }
            $resp = $null; try { $resp = PR-Api $Db $pv $path $q } catch { if ($_.Exception.Message -eq 'PRCollect') { throw }; PR-Log "[$pv] search failed for `"$Title`": $($_.Exception.Message)"; continue }
            foreach ($r in @(@($resp.results) | Where-Object { $_ } | Select-Object -First 8)) {
                $k = "$pv|$($r.id)"; if ($seen.ContainsKey($k)) { continue }; $seen[$k] = $true
                if ($Kind -eq 'show') { $nm = [string]$r.name; $ry = PR-Year $r.first_air_date } else { $nm = [string]$r.title; $ry = PR-Year $r.release_date }
                if (-not $nm) { continue }
                $ov = ''; if ($r.PSObject.Properties['overview'] -and $r.overview) { $ov = ([string]$r.overview) -replace '\s+', ' '; if ($ov.Length -gt 200) { $ov = $ov.Substring(0, 200) + '...' } }
                $out.Add([pscustomobject]@{ Provider = $pv; Id = $r.id; Title = $nm; Year = $ry; Overview = $ov; Sim = [math]::Round((PR-Sim $Title $nm), 2) })
            }
        }
    }
    $arr = [object[]]$out.ToArray()
    $sorted = @($arr | Sort-Object -Property @{ Expression = { $_.Sim }; Descending = $true }, @{ Expression = { if ($Year -and $_.Year -eq [int]$Year) { 0 } else { 1 } } })
    return $sorted   # callers wrap in @()
}
function Get-PRById($Db, [string]$Kind, [string]$Provider, [string]$Id) {
    try {
        if ($Provider -eq 'tvdb') {
            if (-not $Db.Tvdb.Key) { PR-Log 'TVDB ID search needs a TVDB API key in Setup.'; return $null }
            $j = PR-TvdbRaw $Db $(if ($Kind -eq 'show') { "/series/$Id/extended" } else { "/movies/$Id/extended" }) @{ meta = 'translations' }
            if (-not $j -or -not $j.data) { return $null }
            $nm = [string]$j.data.name; try { $tr = @($j.data.translations.nameTranslations | Where-Object { $_.language -eq 'eng' -and $_.name }); if ($tr.Count) { $nm = [string]$tr[0].name } } catch { }
            $y = [string]$j.data.year; if (-not $y -and $j.data.firstAired) { $y = ([string]$j.data.firstAired).Substring(0, 4) }
            return [pscustomobject]@{ Provider = 'tvdb'; Id = $Id; Title = (PR-StripYear $nm); Year = $(if ($y -match '^\d{4}$') { [int]$y } else { $null }); Overview = ''; Sim = 1.0 }
        }
        $d = PR-Api $Db 'tmdb' $(if ($Kind -eq 'show') { "/tv/$Id" } else { "/movie/$Id" }) @{}
        if (-not $d) { return $null }
        if ($Kind -eq 'show') { $nm = [string]$d.name; $y = PR-Year $d.first_air_date } else { $nm = [string]$d.title; $y = PR-Year $d.release_date }
        if (-not $nm) { return $null }
        return [pscustomobject]@{ Provider = 'tmdb'; Id = $d.id; Title = $nm; Year = $y; Overview = ''; Sim = 1.0 }
    } catch { PR-Log "ID lookup failed for $Provider $Id : $($_.Exception.Message)"; return $null }
}
# re-plan one group (a movie, or a whole show) with the match the user chose; the rest of the plan is kept as it is
function Update-PRPlanGroup($Rows, [string]$GroupKey, $Choice, $Db, [string]$MoviesRoot, [string]$SeriesRoot, [bool]$ProbeReal = $false, [bool]$FolderLoose = $true) {
    $mine = @($Rows | Where-Object { $_.group_key -eq $GroupKey })
    if ($mine.Count -eq 0) { return ,@($Rows) }
    $others = @($Rows | Where-Object { $_.group_key -ne $GroupKey })
    $new = New-PRPlan -Paths @($mine | ForEach-Object { $_.old_path }) -MoviesRoot $MoviesRoot -SeriesRoot $SeriesRoot -Db $Db -ProbeReal $ProbeReal -FolderLoose $FolderLoose -Force $(if ($null -ne $Choice) { @{ $GroupKey = $Choice } } else { @{} }) -OtherPaths @($others | ForEach-Object { $_.old_path })   # New-PRPlan returns the row array as one object
    $used = @{}; foreach ($o in $others) { foreach ($t in $o.new_path, $o.fold_path) { if ($t) { $used[$t.ToLowerInvariant()] = $o.old_path } } }
    foreach ($r in $new) { if ($r.new_path -and $used.ContainsKey($r.new_path.ToLowerInvariant())) { $r.note = "DUPLICATE: same target as $($used[$r.new_path.ToLowerInvariant()]); " + $r.note; $r.new_path = ''; $r.accepted = '' } }
    $byOld = @{}; foreach ($r in $new) { $byOld[$r.old_path.ToLowerInvariant()] = $r }
    $res = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Rows) { $k = $r.old_path.ToLowerInvariant(); if ($r.group_key -eq $GroupKey -and $byOld.ContainsKey($k)) { $res.Add($byOld[$k]) } else { $res.Add($r) } }
    return ,$res.ToArray()
}

# ---------- apply / undo (never overwrites) ----------
function PR-NativeDir([string]$p) { return [IO.Path]::GetDirectoryName($p) }
function PR-MoveKeepTimes([string]$From, [string]$To, [bool]$CaseOnly = $false) {
    # Moves a file and keeps its created / modified / accessed times. A same-drive move is a plain rename and
    # already keeps them; the check below restores any time that changed (e.g. a move that had to copy).
    $c = [IO.File]::GetCreationTimeUtc($From); $w = [IO.File]::GetLastWriteTimeUtc($From); $a = [IO.File]::GetLastAccessTimeUtc($From)
    if ($CaseOnly) { $tmp = $To + '.renametmp'; [IO.File]::Move($From, $tmp); [IO.File]::Move($tmp, $To) }
    else { [IO.File]::Move($From, $To) }   # File.Move never overwrites
    try {
        if ([IO.File]::GetLastWriteTimeUtc($To) -ne $w) { [IO.File]::SetLastWriteTimeUtc($To, $w) }
        if ([IO.File]::GetCreationTimeUtc($To) -ne $c) { [IO.File]::SetCreationTimeUtc($To, $c) }
        if ([IO.File]::GetLastAccessTimeUtc($To) -ne $a) { [IO.File]::SetLastAccessTimeUtc($To, $a) }
    } catch { PR-Log "Note: moved, but could not restore the file times of $To : $($_.Exception.Message)" }
}
# ---------- folder letter case and empty folders ----------
$script:PR_KEEP_DIRS = @('$recycle.bin', 'system volume information', '#recycle', '@eadir', '#snapshot', 'recycler')
function PR-Forbidden([string]$p) { return ([string]::IsNullOrWhiteSpace($p) -or $p.TrimStart().ToUpperInvariant().StartsWith('Z:')) }   # never touch Z:
function PR-RootOf([string]$p, [string[]]$Roots) {
    $best = $null
    foreach ($r in $Roots) { if (-not $r) { continue }; $rt = $r.TrimEnd('\'); if ($p.StartsWith($rt + '\', [StringComparison]::OrdinalIgnoreCase) -and ($null -eq $best -or $rt.Length -gt $best.Length)) { $best = $rt } }
    return $best
}
function PR-MoveDirCase([string]$From, [string]$To) {
    # Windows ignores letter case, so a case-only folder rename goes through a temporary name
    $tmp = $From + '.renametmp' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    [IO.Directory]::Move($From, $tmp); [IO.Directory]::Move($tmp, $To)
}
# ---------- season folders (Setup: Standardize season folder names) ----------
$script:PR_SEASON_FIX = $false
$script:PR_SEASON_RX = [regex]'(?i)^(?:season|series|s)[ ._-]*0*(\d{1,3})(?:[ ._-]*\(\d{4}\))?$'
$script:PR_SEASON_FORMAT_DEFAULT = 'Season {NN}'
$script:PR_SEASON_FORMAT = 'Season {NN}'
function Test-PRSeasonFormat([string]$Format) {
    # valid: exactly one of {N} / {NN} / {NNN}, no characters Windows forbids in a folder name, not empty, no trailing space or dot. Returns '' when valid, else the reason.
    if ([string]::IsNullOrWhiteSpace($Format)) { return 'The format is empty.' }
    $toks = [regex]::Matches($Format, '\{N{1,3}\}')
    if ($toks.Count -ne 1) { return 'Use exactly one number token: {N}, {NN} or {NNN}.' }
    $rest = $Format.Remove($toks[0].Index, $toks[0].Length)
    if ($rest -match '[{}]') { return 'Unknown token: only {N}, {NN} or {NNN} are allowed.' }
    if ($rest.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $rest -match '[\\/:*?"<>|]') { return 'The format contains a character that is not allowed in folder names (\ / : * ? " < > |).' }
    if ($Format -ne $Format.Trim() -or $Format.EndsWith('.')) { return 'The format cannot start or end with a space, or end with a dot.' }
    return ''
}
function PR-FormatSeason([int]$n, [string]$Format = $script:PR_SEASON_FORMAT) {
    if (Test-PRSeasonFormat $Format) { $Format = $script:PR_SEASON_FORMAT_DEFAULT }
    $m = [regex]::Match($Format, '\{N{1,3}\}'); $w = $m.Length - 2
    return $Format.Substring(0, $m.Index) + $n.ToString('0' * $w) + $Format.Substring($m.Index + $m.Length)
}
function PR-SeasonFormatRegex([string]$Format) {
    # the format itself as a pattern ('Staffel {NN}' -> ^Staffel\s*0*(\d{1,3})$), so variants of a custom format are recognised too
    if (Test-PRSeasonFormat $Format) { $Format = $script:PR_SEASON_FORMAT_DEFAULT }
    $m = [regex]::Match($Format, '\{N{1,3}\}')
    $pre = [regex]::Escape($Format.Substring(0, $m.Index).Trim()); $post = [regex]::Escape($Format.Substring($m.Index + $m.Length).Trim())
    return [regex]('(?i)^' + $pre + '[ ._-]*0*(\d{1,3})[ ._-]*' + $post + '$')
}
function PR-SeasonFolderName([string]$Name, [string]$Dir) {
    # 'Season 1', 'season1', 'S1', 'S01', 'Season_1', 'Series 1', 'Season 1 (2010)' -> 'Season 01'; 'Specials' / 'Season 0' -> 'Season 00' only when its episodes are named S00Exx; $null = leave as is
    $n = -1; $m = $script:PR_SEASON_RX.Match($Name.Trim()); if (-not $m.Success) { $m = (PR-SeasonFormatRegex $script:PR_SEASON_FORMAT).Match($Name.Trim()) }
    if ($m.Success) { $n = [int]$m.Groups[1].Value } elseif ($Name.Trim() -match '^(?i)specials?$') { $n = 0 }
    if ($n -lt 0) { return $null }
    if ($n -eq 0) {
        $s00 = $false; try { foreach ($f in [IO.Directory]::GetFiles($Dir)) { if ([IO.Path]::GetFileName($f) -match '(?i)(?<![a-z0-9])S00E\d') { $s00 = $true; break } } } catch { }
        if (-not $s00) { return $null }
    }
    return (PR-FormatSeason $n)
}
function Test-PRSeasonRow($r) { return ($r.media_type -eq 'season folder') }
function Get-PRSeasonFolderRows([string]$SeriesRoot) {
    # one row per season folder (Series\<show>\<season>) whose name does not match the season folder format; a target that already exists (or that another folder of the show will get) is a collision (never merged)
    $out = New-Object System.Collections.Generic.List[object]
    $rt = $SeriesRoot.TrimEnd('\'); if ((PR-Forbidden $rt) -or $rt.Length -le 3 -or -not [IO.Directory]::Exists($rt)) { return $out.ToArray() }
    foreach ($show in @(try { [IO.Directory]::GetDirectories($rt) } catch { @() })) {
        if (PR-SkipDir $show) { continue }
        $planned = @{}
        foreach ($sd in @(try { [IO.Directory]::GetDirectories($show) } catch { @() })) {
            if (PR-SkipDir $sd) { continue }
            $nm = [IO.Path]::GetFileName($sd); $want = PR-SeasonFolderName $nm $sd
            if (-not $want -or $want -ceq $nm) { continue }
            $to = $show + '\' + $want
            $row = PR-NewRow $sd; $row.media_type = 'season folder'; $row.confidence = 'high'
            if (($want -ine $nm -and [IO.Directory]::Exists($to)) -or $planned.ContainsKey($want.ToLowerInvariant())) { $row.note = "COLLISION: season folder '$nm' -> '$want', but '$want' already exists" + $(if ($planned.ContainsKey($want.ToLowerInvariant())) { " (another folder of this show becomes '$want')" } else { '' }) + '; not merged, left as is' }
            else { $planned[$want.ToLowerInvariant()] = 1; $row.new_path = $to; $row.note = "season folder: '$nm' -> '$want'" + $(if ($want -ieq $nm) { ' (letter case)' } else { '' }) }
            $out.Add($row)
        }
    }
    return $out.ToArray()
}
function Invoke-PRSeasonFolders($Rows, $Log) {
    # renames each season folder in place (same parent, no copying); case-only through a temporary name; the folder's and its parent's timestamps are kept
    $done = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($Rows | Where-Object { (Test-PRSeasonRow $_) -and $_.new_path })) {
        if (PR-Cancelled) { break }
        if ($script:PR_ONLY_TICKED -and -not ($r.PSObject.Properties['accepted'] -and $r.accepted -eq 'yes')) { continue }
        if (Test-PRSkipped $r) { PR-Log "Season folder left as is (unticked): $($r.old_path)"; continue }
        $from = [string]$r.old_path; $to = [string]$r.new_path
        if ((PR-Forbidden $from) -or (PR-NativeDir $from) -ine (PR-NativeDir $to)) { PR-Log "Season folder kept (protected or not the same parent): $from"; continue }
        if (-not [IO.Directory]::Exists($from)) { PR-Log "SKIP season folder not found: $from"; continue }
        $caseOnly = ($from -ieq $to)
        if (-not $caseOnly -and ([IO.Directory]::Exists($to) -or [IO.File]::Exists($to))) { PR-Log "COLLISION season folder target exists, not merged: $to"; continue }
        try {
            $times = PR-TimesOf $from; $parent = PR-NativeDir $from; $pt = PR-TimesOf $parent
            if ($caseOnly) { PR-MoveDirCase $from $to } else { [IO.Directory]::Move($from, $to) }
            PR-SetTimes $to $times; PR-SetTimes $parent $pt
            $Log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $from; new_path = $to; created_dir = ''; how = 'seasondir'; times = $times })
            $done.Add([pscustomobject]@{ From = $from; To = $to })
            PR-Log "Season folder renamed: $from -> $(PR-Base $to)"
        } catch { PR-Log "FAILED season folder $from : $($_.Exception.Message)" }
    }
    return $done.ToArray()
}
function PR-MapSeasonPath([string]$p, $Map) {
    foreach ($m in $Map) { if ($p.StartsWith($m.From + '\', [StringComparison]::OrdinalIgnoreCase)) { return $m.To + $p.Substring($m.From.Length) } }
    return $p
}
function Get-PRSeasonLine($rows) { $n = @($rows | Where-Object { (Test-PRSeasonRow $_) -and $_.new_path }).Count; $c = @($rows | Where-Object { (Test-PRSeasonRow $_) -and -not $_.new_path }).Count; return "Season folders to standardize: $n" + $(if ($c) { " ($c collision(s) left as they are)" } else { '' }) }
function PR-FixDirCase([string]$Dir, [string[]]$Roots) {
    # makes the existing folders under a library root match the letter case of $Dir (the root itself is never renamed)
    $done = New-Object System.Collections.Generic.List[object]
    if (PR-Forbidden $Dir) { return $done.ToArray() }
    $root = PR-RootOf $Dir $Roots; if (-not $root) { return $done.ToArray() }
    $cur = $root
    foreach ($part in $Dir.Substring($root.Length + 1).Split('\')) {
        if (-not $part) { continue }
        $want = $cur + '\' + $part
        if (-not [IO.Directory]::Exists($want)) { break }
        $actual = $null; foreach ($d in [IO.Directory]::GetDirectories($cur, $part)) {   # names cannot contain * or ?, so the name works as a pattern
            $nm = [IO.Path]::GetFileName($d); if ($nm -ieq $part) { $actual = $nm; break } }
        if ($actual -and $actual -cne $part) {
            $from = $cur + '\' + $actual; PR-MoveDirCase $from $want
            $done.Add([pscustomobject]@{ From = $from; To = $want }); PR-Log "Folder case fixed: $actual -> $part"
        }
        $cur = $want
    }
    return $done.ToArray()
}
# ---------- .nfo clean-up (Setup: Delete .nfo files during Full Run) ----------
$script:PR_DELETE_NFO = $false
function PR-SkipDir([string]$Dir) {
    # hidden / system / reparse folders and the Recycle Bin, System Volume Information, #recycle, @eaDir, #snapshot are never touched
    try { $at = [IO.File]::GetAttributes($Dir) } catch { return $true }
    if ($at -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReparsePoint)) { return $true }
    return ($script:PR_KEEP_DIRS -contains ([IO.Path]::GetFileName($Dir)).ToLowerInvariant())
}
function PR-NfoAllowed([string]$p, [string[]]$Roots) {
    if (PR-Forbidden $p) { return $false }
    $root = PR-RootOf $p @($Roots | Where-Object { $_ -and -not (PR-Forbidden $_) }); if (-not $root -or $root.Length -le 3) { return $false }
    try { $fa = [IO.File]::GetAttributes($p); if ($fa -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System)) { return $false } } catch { return $false }
    $d = PR-NativeDir $p
    while ($d -and $d.Length -gt $root.Length) { if (PR-SkipDir $d) { return $false }; $d = PR-NativeDir $d }
    return $true
}
function Get-PRNfoFiles([string[]]$Roots) {
    # every .nfo under the Movies / Series roots that may be deleted (same exclusions as the empty-folder clean-up)
    $out = New-Object System.Collections.Generic.List[string]; $seen = @{}
    foreach ($r in $Roots) {
        if (PR-Forbidden $r) { continue }
        $rt = $r.TrimEnd('\'); if ($rt.Length -le 3 -or $seen.ContainsKey($rt.ToLowerInvariant()) -or -not [IO.Directory]::Exists($rt)) { continue }
        $seen[$rt.ToLowerInvariant()] = 1
        $stack = New-Object System.Collections.Generic.Stack[string]; $stack.Push($rt)
        while ($stack.Count) {
            $d = $stack.Pop()
            try { foreach ($f in [IO.Directory]::GetFiles($d, '*.nfo')) { if ((PR-SplitExt $f)[1] -ieq '.nfo' -and (PR-NfoAllowed $f @($rt))) { $out.Add($f) } } } catch { }
            try { foreach ($sd in [IO.Directory]::GetDirectories($d)) { if (-not (PR-SkipDir $sd)) { $stack.Push($sd) } } } catch { }
        }
    }
    return $out.ToArray()
}
function PR-HasRecycleBin([string]$p) {
    # only local fixed drives have a Recycle Bin; on a network share or removable drive Windows would delete for good
    if ($p.StartsWith('\\')) { return $false }
    try { return ((New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($p))).DriveType -eq [IO.DriveType]::Fixed) } catch { return $false }
}
function PR-RecycleFile([string]$p) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
}
function Remove-PRNfoFiles([string[]]$Roots, $Log, $Skip = @{}) {
    $n = 0; $kept = 0
    foreach ($f in (Get-PRNfoFiles $Roots)) {
        if (PR-Cancelled) { break }
        if ($Skip -and $Skip.ContainsKey($f.ToLowerInvariant())) { PR-Log "NFO kept (unticked): $f"; $kept++; continue }
        if (-not (PR-HasRecycleBin $f)) { PR-Log "NFO kept (no Recycle Bin on this drive): $f"; $kept++; continue }
        try {
            $parent = PR-NativeDir $f; $pt = PR-TimesOf $parent
            PR-RecycleFile $f
            PR-SetTimes $parent $pt
            $Log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $f; new_path = ''; created_dir = ''; how = 'recycle'; times = '' })
            PR-Log "NFO sent to the Recycle Bin: $f"; $n++
        } catch { PR-Log "Could not delete $f : $($_.Exception.Message)" }
    }
    return @{ Recycled = $n; Kept = $kept }
}
# ---------- duplicate subtitles (Setup: Recycle duplicate subtitles during Full Run) ----------
$script:PR_RECYCLE_DUPSUBS = $false
function Test-PRDupSubRow($r) { return ([string]$r.note).StartsWith('DUPLICATE sidecar target') -and ([string]$r.note).Contains('will be recycled') -and $r.PSObject.Properties['dup_of'] -and [string]$r.dup_of }
function Get-PRDupSubLine($rows) { $n = @($rows | Where-Object { (Test-PRDupSubRow $_) -and -not (Test-PRSkipped $_) }).Count; return "Duplicate subtitles: $n (sent to the Recycle Bin on Full Run)" }
function Remove-PRDupSubs($Rows, $Log) {
    # sends the extra copies of a subtitle (same language already placed next to the video) to the Recycle Bin; the kept copy, videos and .nfo files are never touched
    $n = 0; $kept = 0
    foreach ($r in @($Rows | Where-Object { Test-PRDupSubRow $_ })) {
        if (PR-Cancelled) { break }
        if (Test-PRSkipped $r) { PR-Log "Duplicate subtitle kept (unticked): $($r.old_path)"; $kept++; continue }
        $f = [string]$r.old_path; $keep = [string]$r.dup_of
        $ext = (PR-SplitExt $f)[1].ToLowerInvariant()
        if ((PR-Forbidden $f) -or $ext -eq '.nfo' -or -not ($script:PR_SIDECAR -contains $ext)) { PR-Log "Duplicate subtitle kept (not a subtitle or protected): $f"; $kept++; continue }
        if (-not [IO.File]::Exists($f)) { continue }
        if ($keep.ToLowerInvariant() -eq $f.ToLowerInvariant() -or -not [IO.File]::Exists($keep)) { PR-Log "Duplicate subtitle kept (the copy to keep is not in place: $keep): $f"; $kept++; continue }
        if (-not (PR-HasRecycleBin $f)) { PR-Log "Duplicate subtitle kept (no Recycle Bin on this drive): $f"; $kept++; continue }
        try {
            $parent = PR-NativeDir $f; $pt = PR-TimesOf $parent
            PR-RecycleFile $f
            PR-SetTimes $parent $pt
            $Log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $f; new_path = ''; created_dir = ''; how = 'recycle'; times = '' })
            PR-Log "Duplicate subtitle sent to the Recycle Bin: $f (kept: $keep)"; $n++
        } catch { PR-Log "Could not recycle $f : $($_.Exception.Message)"; $kept++ }
    }
    return @{ Recycled = $n; Kept = $kept }
}
function Get-PRNfoLine($rows) { $n = @($rows | Where-Object { ([string]$_.note).StartsWith('nfo: delete') }).Count; return "NFO files: $n (sent to Recycle Bin on Full Run)" }
function PR-EmptyWalk([string]$Dir, $Out, [bool]$IsRoot) {
    # true when $Dir holds no files at all (hidden ones count) and every subfolder is removable too; adds removable folders children-first
    try {
        if (-not $IsRoot) {
            $at = [IO.File]::GetAttributes($Dir)
            if ($at -band ([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System -bor [IO.FileAttributes]::ReparsePoint)) { return $false }
            if ($script:PR_KEEP_DIRS -contains ([IO.Path]::GetFileName($Dir)).ToLowerInvariant()) { return $false }
        }
        $empty = (@([IO.Directory]::GetFiles($Dir)).Count -eq 0)
        foreach ($sub in [IO.Directory]::GetDirectories($Dir)) { if (-not (PR-EmptyWalk $sub $Out $false)) { $empty = $false } }
        if ($empty -and -not $IsRoot) { $Out.Add($Dir) }
        return $empty
    } catch { return $false }
}
function Get-PREmptyFolders([string[]]$Roots) {
    # every completely empty folder under the Movies / Series roots, deepest first (the roots themselves are never listed)
    $out = New-Object System.Collections.Generic.List[string]; $seen = @{}
    foreach ($r in $Roots) {
        if (PR-Forbidden $r) { continue }
        $rt = $r.TrimEnd('\'); if ($rt.Length -le 3 -or $seen.ContainsKey($rt.ToLowerInvariant()) -or -not [IO.Directory]::Exists($rt)) { continue }   # never a drive root
        $seen[$rt.ToLowerInvariant()] = 1; [void](PR-EmptyWalk $rt $out $true)
    }
    return $out.ToArray()   # callers wrap in @()
}
function PR-TimesOf([string]$p) { return ('{0}|{1}' -f [IO.Directory]::GetCreationTimeUtc($p).Ticks, [IO.Directory]::GetLastWriteTimeUtc($p).Ticks) }
function PR-SetTimes([string]$p, [string]$t) {
    if (-not $t) { return }; $x = $t.Split('|'); if ($x.Count -ne 2) { return }
    try { [IO.Directory]::SetCreationTimeUtc($p, (New-Object DateTime([long]$x[0], 'Utc'))); [IO.Directory]::SetLastWriteTimeUtc($p, (New-Object DateTime([long]$x[1], 'Utc'))) } catch { }
}
function Remove-PREmptyFolders([string[]]$Roots, $Log) {
    # removes empty folders one by one (Delete without recurse fails on anything not empty); each is added to $Log so Undo recreates it
    $n = 0
    foreach ($d in (Get-PREmptyFolders $Roots)) {
        try {
            if (@([IO.Directory]::GetFileSystemEntries($d)).Count -ne 0) { continue }
            $times = PR-TimesOf $d; $parent = PR-NativeDir $d; $pt = PR-TimesOf $parent
            [IO.Directory]::Delete($d, $false)
            PR-SetTimes $parent $pt   # the folder above keeps its modified time
            $Log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $d; new_path = ''; created_dir = ''; how = 'rmdir'; times = $times })
            PR-Log "Removed empty folder: $d"; $n++
        } catch { PR-Log "Could not remove empty folder $d : $($_.Exception.Message)" }
    }
    return $n
}
function Invoke-PRApply {
    param($Rows, [switch]$HighOnly, [string]$UndoLog, [string[]]$Roots = @(), [switch]$RemoveEmpty, [switch]$DeleteNfo, [switch]$RecycleDupSubs, [switch]$FixSeasons)
    $cols = @('moved_at','old_path','new_path','created_dir','how','times'); $fixed = 0; $removed = 0
    $todo = @($Rows | Where-Object { -not (Test-PRSeasonRow $_) -and (PR-ApplyTarget $_ ([bool]$HighOnly)) })
    $log = New-Object System.Collections.Generic.List[object]; $wrote = 0
    $smap = @(); if ($FixSeasons) { $smap = @(Invoke-PRSeasonFolders $Rows $log); if ($smap.Count) { Add-PRCsvRows $log $UndoLog $cols ([ref]$wrote) } }   # season folders first: episode moves then use the new folder paths
    $moved = 0; $skipped = 0; $failed = 0; $n = 0; $stopped = $false
    foreach ($r in $todo) {
        $n++; PR-Progress $n $todo.Count 'Moving files'
        if (PR-Cancelled) { PR-Log 'Stopped by user.'; $stopped = $true; break }
        $old = $r.old_path; $new = PR-ApplyTarget $r ([bool]$HighOnly)
        if ($smap.Count) { $old = PR-MapSeasonPath $old $smap; $new = PR-MapSeasonPath $new $smap }   # paths inside a renamed season folder
        try {
            if (-not [IO.File]::Exists($old)) { PR-Log "SKIP missing source: $old"; $skipped++; continue }
            # folders that differ only in letter case are renamed themselves (otherwise the same files come back on every run)
            foreach ($fx in (PR-FixDirCase (PR-NativeDir $new) $Roots)) {
                $log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $fx.From; new_path = $fx.To; created_dir = ''; how = 'dircase'; times = '' }); $fixed++
                if ($old.StartsWith($fx.From + '', [StringComparison]::OrdinalIgnoreCase)) { $old = $fx.To + $old.Substring($fx.From.Length) }
                Add-PRCsvRows $log $UndoLog $cols ([ref]$wrote)
            }
            if ($old.ToLowerInvariant() -eq $new.ToLowerInvariant() -and (PR-Base $old) -ceq (PR-Base $new)) { continue }   # only the folder case differed: done
            $caseOnly = ($old.ToLowerInvariant() -eq $new.ToLowerInvariant())
            if (-not $caseOnly -and ([IO.File]::Exists($new) -or [IO.Directory]::Exists($new))) { PR-Log "SKIP target exists: $new"; $skipped++; continue }
            $dir = PR-NativeDir $new; $created = ''
            if (-not [IO.Directory]::Exists($dir)) {
                $created = $dir; $up = PR-NativeDir $dir
                while ($up -and -not [IO.Directory]::Exists($up)) { $created = $up; $up = PR-NativeDir $up }
                [void][IO.Directory]::CreateDirectory($dir)
            }
            PR-MoveKeepTimes $old $new $caseOnly   # never overwrites; keeps the file's timestamps
            $how = 'rename'; if ($new -ne [string]$r.new_path) { $how = 'folder-only' } elseif ($HighOnly -and $r.confidence -ne 'high') { $how = 'accepted' }
            $log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $old; new_path = $new; created_dir = $created; how = $how; times = '' })
            $moved++
            Add-PRCsvRows $log $UndoLog $cols ([ref]$wrote)   # incremental so a crash keeps a usable log
        } catch { PR-Log "FAILED $old : $($_.Exception.Message)"; $failed++ }
    }
    $dup = @{ Recycled = 0; Kept = 0 }
    if ($RecycleDupSubs -and -not $stopped) { $dup = Remove-PRDupSubs $Rows $log; if ($dup.Recycled) { Add-PRCsvRows $log $UndoLog $cols ([ref]$wrote) } }   # after the moves (the kept copy is in place), before the empty-folder clean-up so emptied Subs folders go too
    $nfo = @{ Recycled = 0; Kept = 0 }
    if ($DeleteNfo -and -not $stopped) { $nskip = @{}; foreach ($r in $Rows) { if ((Test-PRSkipped $r) -and ([string]$r.note).StartsWith('nfo: delete')) { $nskip[([string]$r.old_path).ToLowerInvariant()] = 1 } }; $nfo = Remove-PRNfoFiles $Roots $log $nskip; if ($nfo.Recycled) { Add-PRCsvRows $log $UndoLog $cols ([ref]$wrote) } }   # before the empty-folder clean-up, so folders that only held .nfo files go too
    if ($RemoveEmpty -and -not $stopped) { $removed = Remove-PREmptyFolders $Roots $log; if ($removed) { Add-PRCsvRows $log $UndoLog $cols ([ref]$wrote) } }
    $msg = "Moved $moved, skipped $skipped, failed $failed."; if ($FixSeasons) { $msg += " Season folders renamed: $($smap.Count)." }; if ($fixed) { $msg += " Folder letter case fixed: $fixed." }; if ($DeleteNfo) { $msg += " NFO files sent to the Recycle Bin: $($nfo.Recycled)." + $(if ($nfo.Kept) { " NFO files kept (no Recycle Bin on the drive): $($nfo.Kept)." } else { '' }) }; if ($RecycleDupSubs) { $msg += " Duplicate subtitles sent to the Recycle Bin: $($dup.Recycled)." + $(if ($dup.Kept) { " Duplicate subtitles kept: $($dup.Kept)." } else { '' }) }; if ($RemoveEmpty) { $msg += " Empty folders removed: $removed." }
    if ($stopped) { $msg = "Stopped. " + $msg }; if ($log.Count) { $msg += " Undo log: $UndoLog" }
    PR-Log $msg
    return @{ Moved = $moved; Skipped = $skipped; Failed = $failed; Log = $UndoLog; Cancelled = $stopped; CaseFixed = $fixed; Removed = $removed; NfoRecycled = $nfo.Recycled; NfoKept = $nfo.Kept; DupRecycled = $dup.Recycled; DupKept = $dup.Kept; SeasonFixed = $smap.Count }
}
function Invoke-PRUndo {
    param([string]$UndoLog, [switch]$WhatIf)
    $rows = @(Import-Csv -LiteralPath $UndoLog -Encoding UTF8); [Array]::Reverse($rows)
    $ok = 0; $skip = 0; $rec = 0; $n = 0; $made = New-Object System.Collections.Generic.List[object]
    foreach ($r in $rows) {
        $n++; PR-Progress $n $rows.Count 'Undoing'
        $how = ''; if ($r.PSObject.Properties['how']) { $how = [string]$r.how }
        if ($how -eq 'recycle') { $rec++; continue }   # a .nfo or duplicate subtitle sent to the Recycle Bin: restore it from there (Undo lists the count)
        if ($how -eq 'rmdir') {   # a removed empty folder: create it again
            if ($WhatIf) { PR-Log "recreate $($r.old_path)"; continue }
            try { if (-not [IO.Directory]::Exists($r.old_path)) { [void][IO.Directory]::CreateDirectory($r.old_path) }; $made.Add($r); $ok++ } catch { PR-Log "FAILED recreate $($r.old_path) : $($_.Exception.Message)"; $skip++ }
            continue
        }
        if ($how -eq 'seasondir') {   # a renamed season folder: give it its old name back (same parent; timestamps kept)
            if ($WhatIf) { PR-Log "$($r.new_path) -> $($r.old_path)"; continue }
            try {
                if (-not [IO.Directory]::Exists($r.new_path)) { PR-Log "SKIP not found: $($r.new_path)"; $skip++; continue }
                $caseOnly = ([string]$r.old_path -ieq [string]$r.new_path)
                if (-not $caseOnly -and [IO.Directory]::Exists($r.old_path)) { PR-Log "SKIP original folder name occupied: $($r.old_path)"; $skip++; continue }
                $t = PR-TimesOf $r.new_path; $parent = PR-NativeDir $r.new_path; $pt = PR-TimesOf $parent
                if ($caseOnly) { PR-MoveDirCase $r.new_path $r.old_path } else { [IO.Directory]::Move($r.new_path, $r.old_path) }
                PR-SetTimes $r.old_path $t; PR-SetTimes $parent $pt; $ok++
            } catch { PR-Log "FAILED $($r.new_path) : $($_.Exception.Message)"; $skip++ }
            continue
        }
        if ($how -eq 'dircase') {   # a folder whose letter case was changed: change it back
            if ($WhatIf) { PR-Log "$($r.new_path) -> $($r.old_path)"; continue }
            try { if ([IO.Directory]::Exists($r.new_path)) { PR-MoveDirCase $r.new_path $r.old_path; $ok++ } else { PR-Log "SKIP not found: $($r.new_path)"; $skip++ } } catch { PR-Log "FAILED $($r.new_path) : $($_.Exception.Message)"; $skip++ }
            continue
        }
        if (-not [IO.File]::Exists($r.new_path)) { PR-Log "SKIP not found: $($r.new_path)"; $skip++; continue }
        if (([IO.File]::Exists($r.old_path)) -and $r.old_path.ToLowerInvariant() -ne $r.new_path.ToLowerInvariant()) { PR-Log "SKIP original path occupied: $($r.old_path)"; $skip++; continue }
        if ($WhatIf) { PR-Log "$($r.new_path) -> $($r.old_path)"; continue }
        try {
            $d = PR-NativeDir $r.old_path; if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
            PR-MoveKeepTimes $r.new_path $r.old_path ($r.old_path.ToLowerInvariant() -eq $r.new_path.ToLowerInvariant())
            $ok++
            if ($r.created_dir) {
                $p = PR-NativeDir $r.new_path
                while ($p -and $p.StartsWith($r.created_dir, [StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($p) -and @([IO.Directory]::GetFileSystemEntries($p)).Count -eq 0) {
                    [IO.Directory]::Delete($p); $p = PR-NativeDir $p
                }
            }
        } catch { PR-Log "FAILED $($r.new_path) : $($_.Exception.Message)"; $skip++ }
    }
    for ($i = $made.Count - 1; $i -ge 0; $i--) { PR-SetTimes $made[$i].old_path ([string]$made[$i].times) }   # deepest last-created first, so a parent keeps its own time
    PR-Log "Undo: restored $ok, skipped $skip."
    if ($rec) { PR-Log "$rec recycled file(s) (.nfo / duplicate subtitles) are in the Recycle Bin - restore them from there if needed." }
    return @{ Restored = $ok; Skipped = $skip; Recycled = $rec }
}

# ---------- duplicate management (used by the Duplicates dialog) ----------
function PR-ResHint([string]$name) {
    # resolution hint from a file name -> @{ Label; Rank } (Rank 0 = unknown)
    $m = [regex]::Match($name, '(?i)(?<![a-z0-9])(2160p|4k|uhd|1080p|1080i|720p|576p|480p|360p)(?![a-z0-9])')
    if (-not $m.Success) { return @{ Label = ''; Rank = 0 } }
    $l = $m.Groups[1].Value.ToLowerInvariant()
    $rank = @{ '2160p' = 6; '4k' = 6; 'uhd' = 6; '1080p' = 5; '1080i' = 5; '720p' = 4; '576p' = 3; '480p' = 2; '360p' = 1 }[$l]
    if ($l -eq '4k' -or $l -eq 'uhd') { $l = '2160p' }
    return @{ Label = $l; Rank = $rank }
}

# ---------- read the real video resolution from the file header (MKV, MP4/M4V/MOV and AVI); used when the file name has no resolution ----------
$script:PR_ProbeSource = @'
using System;
using System.IO;
using System.Collections.Generic;
public static class PRProbe {
    class Atom { public long Pos, Hdr, Size; public string Type; }
    public static int[] Probe(string path) {
        try {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 65536)) {
                byte[] h = new byte[12]; int n = fs.Read(h, 0, 12); fs.Position = 0;
                if (n >= 4 && h[0] == 0x1A && h[1] == 0x45 && h[2] == 0xDF && h[3] == 0xA3) return Mkv(fs);
                if (n >= 8 && h[4] == 'f' && h[5] == 't' && h[6] == 'y' && h[7] == 'p') return Mp4(fs);
                if (n >= 12 && h[0] == 'R' && h[1] == 'I' && h[2] == 'F' && h[3] == 'F' && h[8] == 'A' && h[9] == 'V' && h[10] == 'I') {
                    byte[] v = new byte[72]; fs.Position = 0; if (fs.Read(v, 0, 72) == 72 && v[24] == 'a' && v[25] == 'v' && v[26] == 'i' && v[27] == 'h') {
                        int w = BitConverter.ToInt32(v, 64), ht = BitConverter.ToInt32(v, 68); if (w > 0 && ht > 0) return new int[] { w, ht };
                    }
                }
            }
        } catch { }
        return null;
    }
    // ---- Matroska / WebM ----
    static long ReadId(Stream s) {
        int b = s.ReadByte(); if (b < 0) return -1;
        int len = 1; int mask = 0x80; while (len <= 4 && (b & mask) == 0) { len++; mask >>= 1; }
        if (len > 4) return -1;
        long id = b; for (int i = 1; i < len; i++) { int c = s.ReadByte(); if (c < 0) return -1; id = (id << 8) | (uint)c; }
        return id;
    }
    static long ReadSize(Stream s) {   // -2 = unknown size, -1 = error
        int b = s.ReadByte(); if (b < 0) return -1;
        int len = 1; int mask = 0x80; while (len <= 8 && (b & mask) == 0) { len++; mask >>= 1; }
        if (len > 8) return -1;
        long v = b & (mask - 1); bool allOnes = (v == (mask - 1));
        for (int i = 1; i < len; i++) { int c = s.ReadByte(); if (c < 0) return -1; v = (v << 8) | (uint)c; if (c != 0xFF) allOnes = false; }
        return allOnes ? -2 : v;
    }
    static long ReadUInt(Stream s, long size) { long v = 0; for (long i = 0; i < size && i < 8; i++) { int c = s.ReadByte(); if (c < 0) return 0; v = (v << 8) | (uint)c; } return v; }
    static int mkvSteps;
    static int[] Mkv(FileStream fs) { mkvSteps = 0; long w = 0, h = 0; MkvWalk(fs, 0, fs.Length, ref w, ref h); return (w > 0 && h > 0) ? new int[] { (int)w, (int)h } : null; }
    static bool MkvWalk(FileStream fs, long pos, long end, ref long pw, ref long ph) {
        while (pos < end && mkvSteps++ < 400) {
            fs.Position = pos;
            long id = ReadId(fs); if (id < 0) return false;
            long size = ReadSize(fs); if (size == -1) return false;
            long dataPos = fs.Position;
            long dataEnd = (size == -2) ? end : dataPos + size; if (dataEnd > end) dataEnd = end;
            if (id == 0x1F43B675) return true;            // Cluster: tracks are before the media data
            if (id == 0x18538067 || id == 0x1654AE6B || id == 0xAE || id == 0xE0) {
                if (MkvWalk(fs, dataPos, dataEnd, ref pw, ref ph)) return true;
                if (id == 0xE0 && pw > 0 && ph > 0) return true;
            } else if (id == 0xB0) { pw = ReadUInt(fs, size); }
            else if (id == 0xBA) { ph = ReadUInt(fs, size); }
            if (size == -2) return false;
            pos = dataEnd;
        }
        return false;
    }
    // ---- MP4 / MOV ----
    static uint BE32(byte[] b, int o) { return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3]; }
    static List<Atom> Kids(FileStream fs, long pos, long end) {
        List<Atom> l = new List<Atom>(); byte[] hd = new byte[16]; int guard = 0;
        while (pos + 8 <= end && guard++ < 500) {
            fs.Position = pos; int n = fs.Read(hd, 0, 16); if (n < 8) break;
            long size = BE32(hd, 0); long hdr = 8; string type = "" + (char)hd[4] + (char)hd[5] + (char)hd[6] + (char)hd[7];
            if (size == 1) { if (n < 16) break; size = ((long)BE32(hd, 8) << 32) | BE32(hd, 12); hdr = 16; }
            else if (size == 0) size = end - pos;
            if (pos + size > end) size = end - pos;
            if (size < hdr) break;
            Atom a = new Atom(); a.Pos = pos; a.Hdr = hdr; a.Size = size; a.Type = type; l.Add(a);
            pos += size;
        }
        return l;
    }
    static int[] Mp4(FileStream fs) {
        foreach (Atom a in Kids(fs, 0, fs.Length)) {
            if (a.Type != "moov") continue;
            foreach (Atom t in Kids(fs, a.Pos + a.Hdr, a.Pos + a.Size)) {
                if (t.Type != "trak") continue;
                int w = 0, h = 0; bool vide = false;
                foreach (Atom k in Kids(fs, t.Pos + t.Hdr, t.Pos + t.Size)) {
                    if (k.Type == "tkhd" && k.Size - k.Hdr >= 16) {
                        byte[] b = new byte[8]; fs.Position = k.Pos + k.Size - 8; fs.Read(b, 0, 8);
                        w = (int)(BE32(b, 0) >> 16); h = (int)(BE32(b, 4) >> 16);
                    } else if (k.Type == "mdia") {
                        foreach (Atom m in Kids(fs, k.Pos + k.Hdr, k.Pos + k.Size)) {
                            if (m.Type == "hdlr" && m.Size - m.Hdr >= 12) {
                                byte[] b = new byte[12]; fs.Position = m.Pos + m.Hdr; fs.Read(b, 0, 12);
                                if (b[8] == 'v' && b[9] == 'i' && b[10] == 'd' && b[11] == 'e') vide = true;
                            }
                        }
                    }
                }
                if (vide && w > 0 && h > 0) return new int[] { w, h };
            }
        }
        return null;
    }
}
'@
function PR-ProbeRes([string]$path) {
    # -> @{ Label; Rank } from the real frame size, or $null when it cannot be read (other containers, locked/missing file)
    try {
        if (-not ('PRProbe' -as [type])) { Add-Type -TypeDefinition $script:PR_ProbeSource -Language CSharp -ErrorAction Stop }
        $wh = [PRProbe]::Probe($path)
    } catch { return $null }
    if (-not $wh -or $wh.Count -lt 2) { return $null }
    $w = [int]$wh[0]; $h = [int]$wh[1]
    if ($w -ge 3400 -or $h -ge 1700) { return @{ Label = '2160p'; Rank = 6 } }
    if ($w -ge 1800 -or $h -ge 1000) { return @{ Label = '1080p'; Rank = 5 } }
    if ($w -ge 1200 -or $h -ge 700)  { return @{ Label = '720p'; Rank = 4 } }
    if ($h -ge 560 -and $w -ge 700)  { return @{ Label = '576p'; Rank = 3 } }
    if ($w -ge 640 -or $h -ge 420)   { return @{ Label = '480p'; Rank = 2 } }
    return @{ Label = '360p'; Rank = 1 }
}
function PR-FormatSize([double]$bytes) {
    if ($bytes -ge 1GB) { return ($bytes / 1GB).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture) + ' GB' }
    return ($bytes / 1MB).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) + ' MB'
}
function Get-PRDuplicateGroups($Rows) {
    # Groups videos that are (a) DUPLICATE rows pointing at the same target and/or (b) MULTIPLE VERSIONS of one movie.
    # Emits one [pscustomobject]@{ Id (int); Kind; Target; Paths (string[]) } per group (unrolled; callers wrap in @()), sidecars excluded (they follow their video).
    $vid = @{}; foreach ($r in $Rows) { if ($r.media_type -eq 'movie' -or $r.media_type -eq 'episode') { $vid[$r.old_path.ToLowerInvariant()] = $r } }
    $parent = @{}
    $find = { param($x) while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }; return $x }
    $union = { param($a, $b) foreach ($k in $a, $b) { if (-not $parent.ContainsKey($k)) { $parent[$k] = $k } }; $ra = & $find $a; $rb = & $find $b; if ($ra -ne $rb) { $parent[$rb] = $ra } }
    $kind = @{}
    $prefix = 'DUPLICATE: same target as '
    foreach ($r in $vid.Values) {
        if (-not $r.note.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
        $rest = $r.note.Substring($prefix.Length); $winner = $null
        $i = $rest.IndexOf('; ')
        while ($i -ge 0) { $cand = $rest.Substring(0, $i).ToLowerInvariant(); if ($vid.ContainsKey($cand)) { $winner = $cand; break }; $i = $rest.IndexOf('; ', $i + 1) }
        if (-not $winner -and $vid.ContainsKey($rest.ToLowerInvariant())) { $winner = $rest.ToLowerInvariant() }
        if ($winner) { & $union $winner $r.old_path.ToLowerInvariant(); $kind[$winner] = 'same target'; $kind[$r.old_path.ToLowerInvariant()] = 'same target' }
    }
    $byDir = @{}
    foreach ($r in $vid.Values) {
        if ($r.media_type -eq 'movie' -and $r.new_path -and $r.note -like '*MULTIPLE VERSIONS*') {
            $d = (PR-Dir $r.new_path).ToLowerInvariant(); if (-not $byDir.ContainsKey($d)) { $byDir[$d] = @() }; $byDir[$d] += $r.old_path.ToLowerInvariant()
        }
    }
    foreach ($g in $byDir.Values) { for ($k = 1; $k -lt $g.Count; $k++) { & $union $g[0] $g[$k] }; foreach ($p in $g) { if ($kind[$p] -eq 'same target') { $kind[$p] = 'both' } else { $kind[$p] = 'multiple versions' } } }
    # COLLISION rows (target already exists): group with other videos of the same TMDB movie
    $byId = @{}
    foreach ($r in $vid.Values) { if ($r.media_type -eq 'movie' -and $r.tmdb_id) { $t = [string]$r.tmdb_id; if (-not $byId.ContainsKey($t)) { $byId[$t] = @() }; $byId[$t] += $r.old_path.ToLowerInvariant() } }
    foreach ($r in $vid.Values) {
        if ($r.media_type -ne 'movie' -or -not $r.tmdb_id -or -not $r.note.StartsWith('COLLISION', [StringComparison]::Ordinal)) { continue }
        $me = $r.old_path.ToLowerInvariant()
        foreach ($o in $byId[[string]$r.tmdb_id]) { if ($o -ne $me) { & $union $o $me; foreach ($p in $o, $me) { if (-not $kind[$p]) { $kind[$p] = 'multiple versions' } } } }
    }
    $groups = @{}
    foreach ($k in @($parent.Keys)) { $root = & $find $k; if (-not $groups.ContainsKey($root)) { $groups[$root] = @() }; $groups[$root] += $k }
    $out = New-Object System.Collections.Generic.List[object]; $id = 0
    # iterate keys (not Values piped): a single group would otherwise be unrolled into its strings and skipped
    $order = @($groups.Keys | Sort-Object { @($groups[$_] | Sort-Object)[0] })
    foreach ($gk in $order) {
        $members = @($groups[$gk])
        if ($members.Count -lt 2) { continue }
        $paths = @($members | ForEach-Object { $vid[$_].old_path } | Sort-Object)
        $kinds = @($members | ForEach-Object { $kind[$_] } | Select-Object -Unique)
        $k = 'same target'; if ($kinds -contains 'both' -or ($kinds -contains 'same target' -and $kinds -contains 'multiple versions')) { $k = 'both' } elseif ($kinds -contains 'multiple versions') { $k = 'multiple versions' }
        $target = ''; foreach ($m in $members) { if ($vid[$m].new_path) { $target = $vid[$m].new_path; if ($k -ne 'same target') { $target = PR-Dir $target }; break } }
        $id++; $out.Add([pscustomobject]@{ Id = [int]$id; Kind = [string]$k; Target = [string]$target; Paths = [string[]]$paths })
    }
    # do NOT use 'return ,$out': callers do @(Get-PRDuplicateGroups ...), which would wrap the whole array as ONE item
    return $out.ToArray()
}
function Get-PRSidecarIndex([string[]]$AllPaths) {
    # built once per list of paths so each sidecar lookup only looks at its own folder (the old per-video scan of every path was very slow)
    $byDir = @{}; $subsDirs = New-Object System.Collections.Generic.List[string]
    foreach ($p in $AllPaths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $d = (PR-Dir $p).ToLowerInvariant(); $se = PR-SplitExt (PR-Base $p)
        $item = [pscustomobject]@{ Path = $p; Lower = $p.ToLowerInvariant(); Base = (PR-Base $p).ToLowerInvariant(); Stem = ([string]$se[0]).ToLowerInvariant(); Ext = ([string]$se[1]).ToLowerInvariant() }
        if (-not $byDir.ContainsKey($d)) { $byDir[$d] = New-Object System.Collections.Generic.List[object]; if (($d + '\').Contains('\subs\')) { $subsDirs.Add($d) } }
        $byDir[$d].Add($item)
    }
    return @{ ByDir = $byDir; SubsDirs = $subsDirs }
}
function Get-PRSidecarsFor([string]$Video, [string[]]$AllPaths, $Index = $null) {
    # sidecars of a video: same folder + same base name (Movie.srt, Movie.en.srt, Movie.nfo), or Subs\<video stem>\*
    if (-not $Index) { $Index = Get-PRSidecarIndex $AllPaths }
    $dir = (PR-Dir $Video).ToLowerInvariant(); $stem = (PR-SplitExt (PR-Base $Video))[0].ToLowerInvariant(); $vl = $Video.ToLowerInvariant()
    $subs = $dir + '\subs\' + $stem + '\'
    $same = $Index.ByDir[$dir]
    $out = New-Object System.Collections.Generic.List[string]
    # other videos in the same folder with a longer stem that also matches (Joker.mkv vs Joker.2019.1080p.mkv) own their sidecars
    $longer = New-Object System.Collections.Generic.List[string]
    if ($same) {
        foreach ($it in $same) {
            if ($script:PR_VIDEO -contains $it.Ext -and $it.Stem.Length -gt $stem.Length -and $it.Stem.StartsWith($stem, [StringComparison]::Ordinal)) { $longer.Add($it.Stem) }
        }
    }
    foreach ($sd in $Index.SubsDirs) {
        if (-not (($sd + '\').StartsWith($subs, [StringComparison]::Ordinal))) { continue }
        foreach ($it in $Index.ByDir[$sd]) { if ($it.Lower -ne $vl -and $script:PR_SIDECAR -contains $it.Ext) { $out.Add($it.Path) } }
    }
    if ($same) {
        foreach ($it in $same) {
            if ($it.Lower -eq $vl -or $script:PR_SIDECAR -notcontains $it.Ext) { continue }
            if ($it.Base.StartsWith($stem + '.', [StringComparison]::Ordinal)) {
                $owned = $false; foreach ($os in $longer) { if ($it.Base.StartsWith($os + '.', [StringComparison]::Ordinal)) { $owned = $true; break } }
                if (-not $owned) { $out.Add($it.Path) }
            }
        }
    }
    return ,([string[]]$out.ToArray())
}
function Select-PRDefaultKeep($Files) {
    # $Files: objects with Rank and Size; returns index of best (highest resolution, then largest, then first)
    $best = 0
    for ($i = 1; $i -lt @($Files).Count; $i++) {
        $a = $Files[$i]; $b = $Files[$best]
        if ($a.Rank -gt $b.Rank -or ($a.Rank -eq $b.Rank -and $a.Size -gt $b.Size)) { $best = $i }
    }
    return $best
}
function Get-PRDeletePlan {
    # $Selections: objects with Group, Label, Path, Keep (bool). Multiple files per group may be kept.
    # Returns @{ Delete = paths of unticked files in groups that keep >=1 file; Invalid = labels of groups that keep none; Skipped = groups keeping everything }
    param($Selections)
    $order = New-Object System.Collections.Generic.List[string]; $map = @{}
    foreach ($s in @($Selections)) {
        $g = [string]$s.Group
        if (-not $map.ContainsKey($g)) { $map[$g] = @{ Label = [string]$s.Label; Keep = 0; Drop = (New-Object System.Collections.Generic.List[string]) }; $order.Add($g) }
        if ([bool]$s.Keep) { $map[$g].Keep++ } else { $map[$g].Drop.Add([string]$s.Path) }
    }
    $del = New-Object System.Collections.Generic.List[object]; $bad = New-Object System.Collections.Generic.List[string]; $skip = 0
    foreach ($g in $order) {
        $e = $map[$g]
        if ($e.Keep -eq 0) { $bad.Add($e.Label); continue }
        if ($e.Drop.Count -eq 0) { $skip++; continue }
        foreach ($p in $e.Drop) { $del.Add([pscustomobject]@{ Path = $p; Group = $g }) }
    }
    return @{ Delete = $del.ToArray(); Invalid = $bad.ToArray(); Skipped = $skip }
}
# ---- network drive detection (mapped NAS drives like Z: must count as network) ----
$script:PRIsWindows = ($env:OS -eq 'Windows_NT')
if ($script:PRIsWindows -and -not ('PRDrive' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class PRDrive {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern uint GetDriveType(string lpRootPathName);
}
'@ -Language CSharp -ErrorAction Stop
    } catch { }
}
$script:PRNetCache = @{}
$script:PRDriveTypeOverride = $null   # tests: scriptblock(letter) -> Win32 drive type code
function Resolve-PRDriveIsNetwork([int]$Code) {
    # Win32 GetDriveType: 0 unknown, 1 no root dir, 2 removable, 3 fixed, 4 remote, 5 cdrom, 6 ramdisk.
    # Only local fixed/removable disks count as local. Anything else (remote, unknown, "no root dir" - e.g. a mapped
    # drive that is invisible because the app runs elevated) is treated as network = permanent delete. Errs on the safe side.
    return -not ($Code -eq 2 -or $Code -eq 3)
}
function Get-PRDriveTypeCode([string]$Letter) {
    if ('PRDrive' -as [type]) { try { return [int][PRDrive]::GetDriveType($Letter + ':\') } catch { } }
    return -1
}
function Test-PRNetworkPath([string]$Path) {
    if (-not $Path) { return $false }
    if ($Path.StartsWith('\\') -or $Path.StartsWith('//')) { return $true }
    if ($Path -notmatch '^[A-Za-z]:') { return $false }
    $L = $Path.Substring(0, 1).ToUpperInvariant()
    if ($script:PRNetCache.ContainsKey($L)) { return $script:PRNetCache[$L] }
    if ($script:PRDriveTypeOverride) { $r = Resolve-PRDriveIsNetwork ([int](& $script:PRDriveTypeOverride $L)); $script:PRNetCache[$L] = $r; return $r }
    $net = $false
    $code = Get-PRDriveTypeCode $L
    if ($code -eq 4) { $net = $true }
    if (-not $net) { try { if ((New-Object IO.DriveInfo($L)).DriveType -eq [IO.DriveType]::Network) { $net = $true } } catch { } }
    if (-not $net -and $script:PRIsWindows) {
        # WMI: DriveType 4 or a ProviderName (UNC of the share) means a mapped network drive
        $d = $null
        try { $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($L):'" -ErrorAction Stop } catch { try { $d = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($L):'" -ErrorAction Stop } catch { } }
        if ($d -and ([int]$d.DriveType -eq 4 -or $d.ProviderName)) { $net = $true }
        # persistent mapping of the (non-elevated) user, visible even when the app runs elevated
        if (-not $net -and (Test-Path -LiteralPath "HKCU:\Network\$L")) { $net = $true }
    }
    if (-not $net -and $code -ge 0) { $net = Resolve-PRDriveIsNetwork $code }
    $script:PRNetCache[$L] = $net
    return $net
}
function Get-PRDeleteSummary($Items) {
    # $Items: objects with Kind video/sidecar and Size. Returns counts, bytes and the header text used by the GUI.
    $v = 0; $s = 0; $b = 0.0
    # NOTE: avoid @($Items) here - Windows PowerShell 5.1 throws 'Argument types do not match' on some List[object] inputs
    $arr = New-Object System.Collections.ArrayList; if ($null -ne $Items) { foreach ($x in $Items) { if ($null -ne $x) { [void]$arr.Add($x) } } }
    foreach ($it in $arr) {
        if ([string]$it.Kind -eq 'video') { $v++ } else { $s++ }
        $sz = 0.0; foreach ($one in @($it.Size)) { $d = 0.0; if ([double]::TryParse([string]$one, [ref]$d)) { $sz += $d } }
        $b = $b + $sz
    }
    $vt = if ($v -eq 1) { '1 video' } else { "$v videos" }
    $st = if ($s -eq 1) { '1 related subtitle/.nfo file' } else { "$s related subtitle/.nfo files" }
    return [pscustomobject]@{ Videos = $v; Sidecars = $s; Bytes = $b; Text = "$vt + $st"; Header = ("Delete {0} and {1} - {2}" -f $vt, $st, (PR-FormatSize $b)) }
}
function Get-PRFoldersToRemove {
    # Folders that will be empty once $Paths are deleted (walking up, never a root or above). Deepest first.
    param([string[]]$Paths, [string[]]$Roots)
    $del = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $Paths) { if (-not [string]::IsNullOrWhiteSpace($p)) { $fp = $p; try { $fp = [IO.Path]::GetFullPath($p) } catch { }; [void]$del.Add($fp) } }
    $rootSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Roots) { if (-not [string]::IsNullOrWhiteSpace($r)) { $fr = $r; try { $fr = [IO.Path]::GetFullPath($r) } catch { }; [void]$rootSet.Add($fr.TrimEnd('\')) } }
    $out = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $del) {
        $d = $null; try { $d = [IO.Path]::GetDirectoryName($p) } catch { }
        while ($d) {
            $dn = $d.TrimEnd('\')
            if ($rootSet.Contains($dn) -or [IO.Path]::GetPathRoot($d).TrimEnd('\') -eq $dn) { break }
            $inside = $false; foreach ($r in $rootSet) { if ($dn.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) { $inside = $true } }
            if (-not $inside) { break }
            if (-not $seen.Add($dn)) { break }
            if (-not [IO.Directory]::Exists($dn)) { break }
            $ok = $true
            try { foreach ($f in [IO.Directory]::EnumerateFiles($dn, '*', 'AllDirectories')) { if (-not $del.Contains($f)) { $ok = $false; break } } } catch { $ok = $false }
            if (-not $ok) { break }
            $out.Add($dn); $d = $null; try { $d = [IO.Path]::GetDirectoryName($dn) } catch { }
        }
    }
    return ,([string[]]@($out | Sort-Object { $_.Length } -Descending))
}
function Remove-PRFiles {
    # $Items: objects with Path, Group, Kind (video/sidecar). Sends to Recycle Bin (network paths: Windows deletes permanently).
    param($Items, [string]$LogPath, [switch]$Permanent, [string[]]$Folders)
    if (-not $Permanent) { try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop } catch { throw 'Microsoft.VisualBasic is not available; cannot use the Recycle Bin.' } }
    $log = New-Object System.Collections.Generic.List[object]
    $del = 0; $fail = 0; $bytes = 0.0; $n = 0; $all = New-Object System.Collections.ArrayList; if ($null -ne $Items) { foreach ($x in $Items) { if ($null -ne $x -and -not [string]::IsNullOrWhiteSpace([string]$x.Path)) { [void]$all.Add($x) } } }
    foreach ($it in $all) {
        $n++; PR-Progress $n $all.Count 'Deleting'
        $p = [string]$it.Path; $size = 0; $method = ''; $result = ''
        try {
            if (-not [IO.File]::Exists($p)) { $result = 'missing (skipped)' }
            else {
                $size = (New-Object IO.FileInfo($p)).Length
                if ($Permanent) { [IO.File]::Delete($p); $method = 'permanent' }
                else {
                    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                    if (Test-PRNetworkPath $p) { $method = 'network path: permanent (or NAS #recycle if enabled)' } else { $method = 'Recycle Bin' }
                }
                if ([IO.File]::Exists($p)) { $result = 'still exists'; $fail++ } else { $result = 'deleted'; $del++; $bytes += $size }
            }
        } catch { $result = 'FAILED: ' + $_.Exception.Message; $fail++ }
        PR-Log "$result : $p"
        $log.Add([pscustomobject][ordered]@{ deleted_at = (Get-Date -Format s); path = $p; kind = $it.Kind; group = $it.Group; size_bytes = $size; method = $method; result = $result })
        Export-PRCsv $log $LogPath @('deleted_at', 'path', 'kind', 'group', 'size_bytes', 'method', 'result')
    }
    $fdel = 0
    foreach ($fd in @($Folders | Where-Object { $_ } | Sort-Object { $_.Length } -Descending)) {
        $result = ''
        try {
            if (-not [IO.Directory]::Exists($fd)) { $result = 'folder missing (skipped)' }
            elseif (@([IO.Directory]::EnumerateFileSystemEntries($fd)).Count -gt 0) { $result = 'folder not empty (kept)' }
            else { [IO.Directory]::Delete($fd, $false); $result = 'folder removed'; $fdel++ }
        } catch { $result = 'folder FAILED: ' + $_.Exception.Message }
        PR-Log "$result : $fd"
        $log.Add([pscustomobject][ordered]@{ deleted_at = (Get-Date -Format s); path = $fd; kind = 'folder'; group = ''; size_bytes = 0; method = 'empty folder'; result = $result })
        Export-PRCsv $log $LogPath @('deleted_at', 'path', 'kind', 'group', 'size_bytes', 'method', 'result')
    }
    PR-Log "Deleted $del file(s), $(PR-FormatSize $bytes); removed $fdel empty folder(s); failed $fail. Log: $LogPath"
    return @{ Deleted = $del; Failed = $fail; Bytes = $bytes; Log = $LogPath; Folders = $fdel }
}

# ---------- subtitles: The Subtitle Database (TSDB, no key/account), English only ----------
# Output next to the video: <stem>.en.srt (standard) and <stem>.en.sdh.srt (SDH/HI). Plex reads both; the rename planner and
# Duplicates already treat '<video stem>.<anything>.srt' as sidecars of that video, so these files follow the video when it is renamed/deleted.
$script:PR_SUB_BASE = 'https://api.thesubtitledb.org/v1'
$script:PR_SUBEXT = @('.srt', '.ass', '.ssa', '.sub', '.vtt', '.smi')
$script:PR_SUB_MINCUES_MOVIE = 100
$script:PR_SUB_MINCUES_EP = 50
$script:PR_SUB_CACHE_DAYS = 3
$script:PR_SUB_SRC = @{ bluray = 'bluray'; blu = 'bluray'; brrip = 'bluray'; bdrip = 'bluray'; bd = 'bluray'; remux = 'bluray'; web = 'web'; webrip = 'web'; webdl = 'web'; amzn = 'web'; nf = 'web'; hulu = 'web'; dsnp = 'web'; hmax = 'web'; atvp = 'web'; hdtv = 'hdtv'; pdtv = 'hdtv'; dvdrip = 'dvd'; dvd = 'dvd'; dvdscr = 'dvd' }
$script:PR_SUB_RES = @{ '2160p' = '2160p'; '4k' = '2160p'; 'uhd' = '2160p'; '1080p' = '1080p'; '1080i' = '1080p'; '720p' = '720p'; '576p' = '576p'; '480p' = '480p'; '360p' = '360p' }
$script:PR_SUB_CODEC = @{ x264 = 'h264'; h264 = 'h264'; avc = 'h264'; x265 = 'h265'; h265 = 'h265'; hevc = 'h265' }
$script:PR_SUB_STOP = @{}
foreach ($w in ('the and you to of a i it in is that this what for on are with not was have be me my we he she they but do don''t i''m your just so no yes know can will if there here all get go at from it''s you''re' -split '\s+')) { $script:PR_SUB_STOP[$w] = $true }
$script:PR_SUB_AD = [regex]'(?i)opensubtitles|open subtitles|\bosdb\b|subscene|addic7ed|podnapisi|yifysubtitles|tvsubtitles|advertise your product|become a vip|vip member|support us and become|\bwww\.|https?://|^\W*(?:sub(?:title)?s?|captions?|captioned|captioning|translated|translation|resynced?|synced|ripped|encoded|corrected|downloaded)\b.{0,30}\b(?:by|from)\b|^\W*(?:synced|sync|resync(?:ed)?)\s*(?:&|and)\s*corrected'

function New-PRSubs {
    # $Db: the TMDB/TVDB context from New-PRTmdb (only needed for id mapping, may be $null). $CachePath: optional JSON cache of TSDB lookups.
    param($Db = $null, [string]$Version = 'dev', [string]$CachePath = '')
    $cache = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    if ($CachePath -and (Test-Path -LiteralPath $CachePath)) {
        try { $obj = [IO.File]::ReadAllText($CachePath, [Text.Encoding]::UTF8) | ConvertFrom-Json; foreach ($e in @($obj)) { if ($null -ne $e) { $cache[[string]$e.k] = $e.v } } }
        catch { PR-Log "Subtitle cache unreadable, starting fresh: $($_.Exception.Message)" }
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    return @{ Db = $Db; UA = "Renamr/$Version"; Cache = $cache; CachePath = $CachePath; Dirty = 0; Last = [Diagnostics.Stopwatch]::StartNew(); DirCache = @{}; Memo = @{}; Lookups = 0; Downloads = 0; DlRemaining = -1; DlReset = 0 }
}
function Save-PRSubsCache($S) {
    if (-not $S.CachePath) { return }
    try {
        $tmp = $S.CachePath + '.tmp'
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($kv in $S.Cache.GetEnumerator()) { $list.Add([pscustomobject]@{ k = $kv.Key; v = $kv.Value }) }
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $list.ToArray() -Depth 8 -Compress), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $S.CachePath) { [IO.File]::Delete($S.CachePath) }
        [IO.File]::Move($tmp, $S.CachePath); $S.Dirty = 0
    } catch { PR-Log "Could not save subtitle cache: $($_.Exception.Message)" }
}

# ----- HTTP (the two functions tests replace) -----
function PR-SubHttp($S, [string]$Url, [bool]$Follow = $true) {
    # one GET; returns @{ Code; Bytes; Headers (lower-case keys); Error }. Never throws for HTTP errors.
    $req = [Net.HttpWebRequest][Net.WebRequest]::Create($Url)
    $req.Method = 'GET'; $req.UserAgent = [string]$S.UA; $req.Timeout = 30000; $req.ReadWriteTimeout = 30000; $req.AllowAutoRedirect = $Follow
    $req.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [Net.WebException] { $resp = $_.Exception.Response; if ($null -eq $resp) { return @{ Code = 0; Bytes = [byte[]]@(); Headers = @{}; Error = $_.Exception.Message } } }
    catch { return @{ Code = 0; Bytes = [byte[]]@(); Headers = @{}; Error = $_.Exception.Message } }
    try {
        $hdr = @{}; foreach ($k in $resp.Headers.AllKeys) { $hdr[([string]$k).ToLowerInvariant()] = [string]$resp.Headers[$k] }
        $ms = New-Object IO.MemoryStream
        try { $st = $resp.GetResponseStream(); $st.CopyTo($ms) } catch {}
        return @{ Code = [int]$resp.StatusCode; Bytes = [byte[]]$ms.ToArray(); Headers = $hdr; Error = '' }
    } finally { $resp.Close() }
}
function PR-SubPace($S, [int]$minMs) { $w = $minMs - $S.Last.ElapsedMilliseconds; if ($w -gt 0) { Start-Sleep -Milliseconds ([int]$w) }; $S.Last.Restart() }
function PR-SubWaitSecs($h) {
    # seconds the server asks us to wait (Retry-After, else RateLimit-Reset); 0 when unknown
    foreach ($k in 'retry-after', 'ratelimit-reset') {
        if ($h -and $h.ContainsKey($k)) { $d = 0.0; if ([double]::TryParse((([string]$h[$k]) -split ',')[0].Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return [int][math]::Ceiling($d) } }
    }
    return 0
}
function PR-SubGetJson($S, [string]$path, $query) {
    # parsed JSON, or $null on 404. 429: waits when short, else throws 'LIMIT:<seconds>'
    $url = $script:PR_SUB_BASE + $path; if ($query -and $query.Count) { $url += '?' + (PR-UrlEncode $query) }
    for ($a = 0; $a -lt 4; $a++) {
        PR-SubPace $S 150; $S.Lookups++
        $r = PR-SubHttp $S $url $true
        $code = [int]$r.Code
        if ($code -eq 200) {
            $rem = 0; if ([int]::TryParse([string]$r.Headers['ratelimit-remaining'], [ref]$rem) -and $rem -le 1) { $w = [math]::Min(60, (PR-SubWaitSecs $r.Headers) + 1); if ($w -gt 1) { Start-Sleep -Seconds $w } }
            $txt = [Text.Encoding]::UTF8.GetString([byte[]]$r.Bytes)
            if (-not $txt.Trim()) { return $null }
            return ($txt | ConvertFrom-Json)
        }
        if ($code -eq 404) { return $null }
        if ($code -eq 429) {
            $w = PR-SubWaitSecs $r.Headers; if ($w -le 0) { $w = 5 * ($a + 1) }
            if ($w -gt 90) { throw "LIMIT:$w" }
            PR-Log "TSDB lookup rate limit; waiting $w s"; Start-Sleep -Seconds $w; continue
        }
        if ($code -eq 0 -or $code -ge 500) { Start-Sleep -Milliseconds ([int](1000 * [math]::Pow(2, $a + 1))); continue }
        throw "TSDB HTTP $code on $path"
    }
    throw "TSDB unreachable for $path"
}
function PR-SubDownload($S, [string]$id) {
    # raw bytes of subtitle $id (GET /get/<id> answers 302 to the file). 429 -> throws 'LIMIT:<seconds>'; gone -> throws 'NOTFOUND'
    $url = "https://api.thesubtitledb.org/get/$id"   # note: no /v1 in the download path
    for ($a = 0; $a -lt 3; $a++) {
        PR-SubPace $S 400
        $r = PR-SubHttp $S $url $false
        $code = [int]$r.Code
        if ($code -eq 429) { throw "LIMIT:$(PR-SubWaitSecs $r.Headers)" }
        if ($code -ge 300 -and $code -lt 400) {
            $loc = [string]$r.Headers['location']
            if (-not $loc) { throw "TSDB gave no download location for $id" }
            if ($loc -notmatch '^https?://') { $loc = 'https://api.thesubtitledb.org' + $loc }
            $rem = 0; if ([int]::TryParse([string]$r.Headers['ratelimit-remaining'], [ref]$rem)) { $S.DlRemaining = $rem; $S.DlReset = PR-SubWaitSecs $r.Headers }
            $f = PR-SubHttp $S $loc $true
            if ([int]$f.Code -eq 200) { $S.Downloads++; return ,[byte[]]$f.Bytes }
            if ([int]$f.Code -eq 429) { throw "LIMIT:$(PR-SubWaitSecs $f.Headers)" }
            if ([int]$f.Code -eq 404 -or [int]$f.Code -eq 410) { throw 'NOTFOUND' }
            Start-Sleep -Milliseconds (1500 * ($a + 1)); continue
        }
        if ($code -eq 200) { $S.Downloads++; return ,[byte[]]$r.Bytes }
        if ($code -eq 404 -or $code -eq 410) { throw 'NOTFOUND' }
        if ($code -eq 0 -or $code -ge 500) { Start-Sleep -Milliseconds (1500 * ($a + 1)); continue }
        throw "TSDB HTTP $code downloading $id"
    }
    throw "TSDB download failed for $id"
}

# ----- candidate handling -----
function PR-SubNameIsSdh([string]$name) { return [bool]([regex]::IsMatch($name, '(?i)(?<![a-z0-9])(sdh|hi|cc|hoh|hearing[ ._-]?impaired|hearing|deaf)(?![a-z0-9])')) }
function PR-SubNameIsJunk([string]$name) { return [bool]([regex]::IsMatch($name, '(?i)commentar|(?<![a-z0-9])forced(?![a-z0-9])|foreign[ ._-]?parts?|karaoke')) }
function PR-SubItems($j) {
    # TSDB response -> plain English-SRT candidate objects (other languages/formats dropped). Returns an array (use $x = PR-SubItems $j).
    $out = New-Object System.Collections.Generic.List[object]
    if ($null -ne $j -and $null -ne $j.subtitles) {
        foreach ($i in @($j.subtitles.items)) {
            if ($null -eq $i) { continue }
            $lang = ([string]$i.language).ToLowerInvariant(); if ($lang -ne 'en' -and $lang -notmatch '^en-[a-z]{2,4}$') { continue }
            $fmt = ([string]$i.format).ToLowerInvariant(); if ($fmt -and $fmt -ne 'srt') { continue }
            $name = ([string]$i.release_name).Trim()
            $hi = $false; if ($null -ne $i.hearing_impaired) { $hi = [bool]$i.hearing_impaired }
            $out.Add([pscustomobject]@{ Id = [string]$i.id; Cues = [int]$i.cues; Duration = [int]$i.duration_s; Bytes = [long]$i.bytes; Encoding = [string]$i.encoding; Name = $name; Hi = $hi; Sdh = [bool]($hi -or (PR-SubNameIsSdh $name)); Added = [string]$i.added_at })
        }
    }
    return ,$out.ToArray()
}
function PR-SubInfo([string]$name) {
    $n = [regex]::Replace($name, '(?i)\.(srt|mkv|mp4|avi|m4v|mov|ts)$', '')
    $res = ''; $src = ''; $codec = ''
    foreach ($t in ([regex]::Split($n.ToLowerInvariant(), '[^a-z0-9]+') | Where-Object { $_ })) {
        if (-not $res -and $script:PR_SUB_RES.ContainsKey($t)) { $res = $script:PR_SUB_RES[$t] }
        if (-not $src -and $script:PR_SUB_SRC.ContainsKey($t)) { $src = $script:PR_SUB_SRC[$t] }
        if (-not $codec -and $script:PR_SUB_CODEC.ContainsKey($t)) { $codec = $script:PR_SUB_CODEC[$t] }
    }
    $grp = ''; $gm = [regex]::Match($n.Trim(), '-\s*\[?([A-Za-z0-9]+)\]?\s*$'); if ($gm.Success) { $grp = $gm.Groups[1].Value.ToLowerInvariant() }
    return @{ Res = $res; Src = $src; Codec = $codec; Group = $grp; Clean = $n }
}
function PR-SubScore($cand, $vi, [double]$median) {
    # similarity of a subtitle's release name to the video's file name (resolution, source, codec, release group, overall text)
    $ci = PR-SubInfo $cand.Name
    $s = 0.0
    if ($vi.Res -and $ci.Res) { if ($vi.Res -eq $ci.Res) { $s += 3 } else { $s -= 1 } }
    if ($vi.Src -and $ci.Src -and $vi.Src -eq $ci.Src) { $s += 2 }
    if ($vi.Codec -and $ci.Codec -and $vi.Codec -eq $ci.Codec) { $s += 1.5 }
    if ($vi.Group -and $ci.Group -and $vi.Group -eq $ci.Group) { $s += 3 }
    $s += 1.5 * (PR-Sim $vi.Clean $ci.Clean)
    if ($median -gt 0) { if ($cand.Cues -lt (0.5 * $median)) { $s -= 3 } elseif ($cand.Cues -lt (0.8 * $median)) { $s -= 1 } }   # noticeably shorter than the other uploads = probably incomplete
    return $s
}
function PR-SubPick($Items, [string]$Stem, [bool]$Episode, [string]$Kind, [int]$Max = 3) {
    # best candidates of $Kind ('standard' = not SDH, 'sdh' = SDH/HI) for a video file name, best first (at most $Max). Returns an array.
    $min = $script:PR_SUB_MINCUES_MOVIE; if ($Episode) { $min = $script:PR_SUB_MINCUES_EP }
    $pool = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Items)) {
        if ($null -eq $c) { continue }
        if (PR-SubNameIsJunk $c.Name) { continue }
        if ($c.Cues -lt $min -or $c.Bytes -lt 2000) { continue }
        if ($Kind -eq 'sdh' -and -not $c.Sdh) { continue }
        if ($Kind -ne 'sdh' -and $c.Sdh) { continue }
        $pool.Add($c)
    }
    if ($pool.Count -eq 0) { return ,@() }
    $cues = @($pool | ForEach-Object { [double]$_.Cues } | Sort-Object); $median = $cues[[int][math]::Floor(($cues.Count - 1) / 2)]
    $vi = PR-SubInfo $Stem
    $scored = foreach ($c in $pool) { [pscustomobject]@{ Score = (PR-SubScore $c $vi $median); Cand = $c } }
    $sorted = @($scored | Sort-Object @{ Expression = { $_.Score }; Descending = $true }, @{ Expression = { $_.Cand.Cues }; Descending = $true }, @{ Expression = { $_.Cand.Added }; Descending = $true }, @{ Expression = { $_.Cand.Id }; Descending = $false })
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($x in $sorted) { if ($out.Count -ge $Max) { break }; $out.Add($x.Cand) }
    return ,$out.ToArray()
}

# ----- text handling -----
function PR-SubDecode([byte[]]$Bytes, [string]$Encoding = '') {
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return [Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3) }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) { return [Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2) }
    try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes) } catch { }   # strict: succeeds only for valid UTF-8
    $enc = $null; $e = $Encoding.ToLowerInvariant()
    if ($e -and $e -notmatch '1252|latin|8859-1|ascii|utf') { try { $enc = [Text.Encoding]::GetEncoding($Encoding) } catch { $enc = $null } }
    if ($null -eq $enc) { try { $enc = [Text.Encoding]::GetEncoding(1252) } catch { $enc = [Text.Encoding]::GetEncoding('iso-8859-1') } }
    return $enc.GetString($Bytes)
}
function PR-SubClean([string]$Text) {
    # drops advertising/credit lines (OpenSubtitles, VIP, URLs, "Subtitles by ..."), cues left empty, and renumbers; CRLF output.
    # -> @{ Text; Cues; Removed }
    $t = $Text.TrimStart([char]0xFEFF).Replace("`r`n", "`n").Replace("`r", "`n").Trim()
    $blocks = [regex]::Split($t, '\n[ \t]*\n+')
    $sb = New-Object Text.StringBuilder; $n = 0; $removed = 0
    foreach ($b in $blocks) {
        $lines = $b.Split("`n"); $ti = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\d{1,3}:\d{2}:\d{2}[,.]\d{1,3}\s*-->') { $ti = $i; break } }
        if ($ti -lt 0) { continue }
        $keep = New-Object System.Collections.Generic.List[string]
        for ($i = $ti + 1; $i -lt $lines.Count; $i++) {
            $plain = ([regex]::Replace($lines[$i], '<[^>]+>|\{\\[^}]*\}', '')).Trim()
            if ($plain -and $script:PR_SUB_AD.IsMatch($plain)) { $removed++; continue }
            $keep.Add($lines[$i].TrimEnd())
        }
        $hasText = $false; foreach ($k in $keep) { if ($k.Trim()) { $hasText = $true; break } }
        if (-not $hasText) { continue }
        $n++
        [void]$sb.Append("$n`r`n" + $lines[$ti].Trim() + "`r`n" + ($keep -join "`r`n") + "`r`n`r`n")
    }
    return @{ Text = $sb.ToString(); Cues = $n; Removed = $removed }
}
function PR-SubLooksEnglish([string]$Text) {
    # heuristic: mostly Latin letters and a high share of common English words
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $Text.Replace("`r", "`n").Split("`n")) { $x = $l.Trim(); if (-not $x -or $x -match '^\d+$' -or $x.Contains('-->')) { continue }; $lines.Add(([regex]::Replace($x, '<[^>]+>', ''))) }
    $all = ($lines -join ' ').ToLowerInvariant()
    $letters = [regex]::Replace($all, '[^\p{L}]', '').Length; $ascii = [regex]::Replace($all, '[^a-z]', '').Length
    if ($letters -lt 100) { return $false }
    if (($ascii / $letters) -lt 0.85) { return $false }
    $words = [regex]::Matches($all, "[a-z]+(?:'[a-z]+)?"); if ($words.Count -lt 30) { return $false }
    $hit = 0; foreach ($w in $words) { if ($script:PR_SUB_STOP.ContainsKey($w.Value)) { $hit++ } }
    return (($hit / $words.Count) -ge 0.25)
}
function PR-SubFetch($S, $cand) {
    # downloads one candidate and validates it. -> @{ Ok; Text; Cues; Why }. LIMIT errors propagate.
    $bytes = PR-SubDownload $S ([string]$cand.Id)
    $txt = PR-SubDecode ([byte[]]$bytes) ([string]$cand.Encoding)
    $c = PR-SubClean $txt
    if ($c.Cues -lt 20) { return @{ Ok = $false; Text = ''; Cues = $c.Cues; Why = 'too few cues' } }
    if (-not (PR-SubLooksEnglish $c.Text)) { return @{ Ok = $false; Text = ''; Cues = $c.Cues; Why = 'not English' } }
    return @{ Ok = $true; Text = $c.Text; Cues = $c.Cues; Why = '' }
}

# ----- files next to the video -----
function Get-PRSubTarget([string]$Video, [string]$Kind) {
    $stem = (PR-SplitExt $Video)[0]
    if ($Kind -eq 'sdh') { return $stem + '.en.sdh.srt' }
    return $stem + '.en.srt'
}
function PR-SubClassify([string]$Middle) {
    # name part between the video stem and the extension ('', 'en', 'en.sdh', 'eng.forced', ...). -> $null when it is not a language tag
    # (e.g. '2019.en' belongs to another, longer-named video) else @{ English; Sdh; Forced; Bare }
    $words = @([regex]::Matches($Middle.ToLowerInvariant(), '[a-z]+') | ForEach-Object { $_.Value })
    if ($Middle -match '\d') { return $null }
    $okw = @('sdh', 'hi', 'cc', 'forced', 'default', 'hearing', 'impaired', 'us', 'gb', 'uk')
    $en = $false; $sdh = $false; $forced = $false
    foreach ($w in $words) {
        if ($w -eq 'en' -or $w -eq 'eng' -or $w -eq 'english') { $en = $true; continue }
        if ($w -eq 'sdh' -or $w -eq 'hi' -or $w -eq 'cc' -or $w -eq 'hearing' -or $w -eq 'impaired') { $sdh = $true; continue }
        if ($w -eq 'forced') { $forced = $true; continue }
        if ($okw -contains $w) { continue }
        if ($script:PR_LANG.ContainsKey($w) -or ($script:PR_LANG.Values -contains $w)) { continue }
        return $null
    }
    return @{ English = $en; Sdh = $sdh; Forced = $forced; Bare = ($words.Count -eq 0) }
}
function Get-PRSubExisting($S, [string]$Video) {
    # which English subtitle files already exist for the video -> @{ Standard; Sdh }.
    # Standard counts any English sidecar that is not SDH/forced (.en.srt, .eng.srt, .English.srt, a bare <stem>.srt, Subs\<stem>\*English*).
    $dir = PR-Dir $Video; $stem = (PR-SplitExt (PR-Base $Video))[0]
    $res = @{ Standard = $false; Sdh = $false }
    $key = $dir.ToLowerInvariant()
    if (-not $S.DirCache.ContainsKey($key)) {
        $names = New-Object System.Collections.Generic.List[string]
        try { foreach ($f in [IO.Directory]::GetFiles($dir)) { $names.Add([IO.Path]::GetFileName($f)) } } catch { }
        $S.DirCache[$key] = $names.ToArray()
    }
    $sl = $stem.ToLowerInvariant() + '.'
    foreach ($n in $S.DirCache[$key]) {
        if (-not $n.ToLowerInvariant().StartsWith($sl, [StringComparison]::Ordinal)) { continue }
        $rest = $n.Substring($stem.Length + 1)   # 'srt' (bare), 'en.srt', 'en.sdh.srt', 'nfo' ...
        $di = $rest.LastIndexOf('.'); $mid = ''; $ext = '.' + $rest.ToLowerInvariant()
        if ($di -ge 0) { $mid = $rest.Substring(0, $di); $ext = $rest.Substring($di).ToLowerInvariant() }
        if ($script:PR_SUBEXT -notcontains $ext) { continue }
        $c = PR-SubClassify $mid
        if ($null -eq $c -or $c.Forced) { continue }
        if ($c.Sdh -and ($c.English -or $c.Bare)) { $res.Sdh = $true; continue }
        if ($c.English -or $c.Bare) { $res.Standard = $true }
    }
    $subs = $dir + '\Subs\' + $stem
    $names2 = @(); try { if ([IO.Directory]::Exists($subs)) { $names2 = @([IO.Directory]::GetFiles($subs) | ForEach-Object { [IO.Path]::GetFileName($_) }) } } catch { }
    foreach ($n in $names2) {
        $e = '.' + $n.Substring($n.LastIndexOf('.') + 1).ToLowerInvariant(); if ($script:PR_SUBEXT -notcontains $e) { continue }
        $ls = PR-LangSuffix ($n.Substring(0, $n.LastIndexOf('.')))
        if ($ls -eq '.en') { $res.Standard = $true } elseif ($ls -eq '.en.sdh') { $res.Sdh = $true }
    }
    return $res
}

# ----- ids and lookups -----
function PR-SubTvdbImdb($db, [string]$id, [string]$kind) {
    # IMDb id of a TVDB series/movie from TVDB's remote ids ('' when none)
    $ck = "tvdb|ids|$kind|$id"
    if ($db.Cache.ContainsKey($ck)) { return [string]$db.Cache[$ck].imdb }
    $path = "/series/$id/extended"; if ($kind -eq 'movie') { $path = "/movies/$id/extended" }
    $j = PR-TvdbRaw $db $path @{ short = 'true' }
    $imdb = ''
    if ($j -and $j.data) { foreach ($r in @($j.data.remoteIds)) { if ($null -ne $r -and ([string]$r.sourceName) -match 'IMDB' -and ([string]$r.id) -match '^tt\d+$') { $imdb = [string]$r.id; break } } }
    $db.Cache[$ck] = [pscustomobject]@{ imdb = $imdb }; $db.Dirty++
    return $imdb
}
function PR-SubResolve($S, [string]$TmdbId, [string]$Kind) {
    # row id -> @{ Type = 'tmdb'|'imdb'; Id } or $null. Kind: 'movie' | 'tv'. 'tvdb:<id>' ids are mapped through TMDB /find (when a TMDB key is set), else through TVDB's IMDb remote id.
    $memo = $S.Memo; $mk = "id|$Kind|$TmdbId"
    if ($memo.ContainsKey($mk)) { return $memo[$mk] }
    $out = $null
    if ($TmdbId -match '^\d+$') { $out = @{ Type = 'tmdb'; Id = $TmdbId } }
    elseif ($TmdbId -match '^tvdb:(\d+)$') {
        $tv = $Matches[1]; $db = $S.Db
        if ($db -and $db.Key) {
            try {
                $f = PR-TmdbGet $db "/find/$tv" @{ external_source = 'tvdb_id' }
                $list = @(); if ($f) { if ($Kind -eq 'movie') { $list = @($f.movie_results) } else { $list = @($f.tv_results) } }
                $list = @($list | Where-Object { $null -ne $_ })
                if ($list.Count -gt 0) { $out = @{ Type = 'tmdb'; Id = [string]$list[0].id } }
            } catch { PR-Log "TMDB id lookup for $TmdbId failed: $($_.Exception.Message)" }
        }
        if (-not $out -and $db -and $db.Tvdb -and $db.Tvdb.Key) {
            try { $imdb = PR-SubTvdbImdb $db $tv $Kind; if ($imdb) { $out = @{ Type = 'imdb'; Id = $imdb } } } catch { PR-Log "TVDB id lookup for $TmdbId failed: $($_.Exception.Message)" }
        }
    }
    $memo[$mk] = $out
    return $out
}
function PR-SubCompact($Items) {
    # what the cache keeps per title: the most useful standard and SDH candidates (the full list can be hundreds of entries)
    $std = @($Items | Where-Object { -not $_.Sdh -and -not (PR-SubNameIsJunk $_.Name) -and $_.Cues -ge 30 } | Sort-Object @{ Expression = { $_.Cues }; Descending = $true } | Select-Object -First 30)
    $sdh = @($Items | Where-Object { $_.Sdh -and -not (PR-SubNameIsJunk $_.Name) -and $_.Cues -ge 30 } | Sort-Object @{ Expression = { $_.Cues }; Descending = $true } | Select-Object -First 15)
    return @($std + $sdh)   # plain return: callers wrap it in @() (a ',' here would nest the array inside the caller's @())
}
function PR-SubLookup($S, [string]$Kind, [string]$IdType, [string]$Id, $Season = 0, $Episode = 0) {
    # English SRT candidates for one movie ($Kind 'movie') or episode ($Kind 'tv'). Returns an array (use $x = PR-SubLookup ...); empty = none.
    $path = "/by-$IdType/$Id"; if ($Kind -eq 'tv') { $path += "/season/$([int]$Season)/episode/$([int]$Episode)" }
    $ck = 'tsdb|' + $path
    $now = [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($S.Cache.ContainsKey($ck)) {
        $c = $S.Cache[$ck]
        if ($c -and ($now - [long]$c.t) -lt (86400 * $script:PR_SUB_CACHE_DAYS)) {
            $flat = New-Object System.Collections.Generic.List[object]
            foreach ($x in @($c.items)) { if ($null -eq $x) { continue }; if ($x -is [System.Array]) { foreach ($y in $x) { if ($null -ne $y) { $flat.Add($y) } } } else { $flat.Add($x) } }
            return ,$flat.ToArray()
        }
    }
    $want = 'movie'; if ($Kind -eq 'tv') { $want = 'tv' }
    $items = New-Object System.Collections.Generic.List[object]
    $offset = 0
    for ($pg = 0; $pg -lt 3; $pg++) {
        $q = @{ lang = 'en'; format = 'srt'; limit = 100 }; if ($offset -gt 0) { $q['offset'] = $offset }
        $j = PR-SubGetJson $S $path $q
        if ($null -eq $j) { break }
        $mt = ''; try { $mt = [string]$j.title.media_type } catch { }
        if ($mt -and $mt -ne $want) { $items.Clear(); break }   # TMDB ids are shared by movies and shows: this id is the other kind
        foreach ($x in (PR-SubItems $j)) { $items.Add($x) }
        $raw = 0; foreach ($x in $j.subtitles.items) { if ($null -ne $x) { $raw++ } }
        $total = 0; try { $total = [int]$j.subtitles.total } catch { }
        $offset += $raw
        if ($raw -eq 0 -or $offset -ge $total) { break }
    }
    $S.Cache[$ck] = [pscustomobject]@{ t = $now; items = @(PR-SubCompact $items.ToArray()) }; $S.Dirty++
    if ($S.Dirty -ge 100) { Save-PRSubsCache $S }
    return ,$items.ToArray()
}

# ----- planning (dry run: lookups only, nothing is downloaded or written) -----
function PR-SubEpOf([string]$path) {
    $m = $script:PR_EP.Match((PR-SplitExt (PR-Base $path))[0])
    if (-not $m.Success) { return $null }
    if ($m.Groups[1].Success) { return @{ S = [int]$m.Groups[1].Value; E = [int]$m.Groups[2].Value } }
    return @{ S = [int]$m.Groups[4].Value; E = [int]$m.Groups[5].Value }
}
function PR-SubStatusText($status, $cands) {
    switch ($status) {
        'found' { $c = @($cands)[0]; return "found ($(@($cands).Count) candidate(s); best: $($c.Name))" }
        'none' { return 'not found' }
        'exists' { return 'already have' }
        'off' { return 'off' }
        default { return [string]$status }
    }
}
function Get-PRSubsPlan {
    # $Rows: scanned plan rows. Returns @{ Items; Std; Sdh; Skipped; Cancelled; Limit }. Each item: Video, Name, Kind, Id, StdStatus/StdCands, SdhStatus/SdhCands, Note
    param($Rows, $S, [switch]$HighOnly, [bool]$Standard = $true, [bool]$Sdh = $true)
    $items = New-Object System.Collections.Generic.List[object]
    $elig = New-Object System.Collections.Generic.List[object]; $skipped = 0
    foreach ($r in @($Rows)) {
        if ($null -eq $r -or ($r.media_type -ne 'movie' -and $r.media_type -ne 'episode')) { continue }
        if (-not [string]$r.tmdb_id) { continue }
        $note = [string]$r.note
        if ($note.StartsWith('DUPLICATE', [StringComparison]::Ordinal) -or $note.StartsWith('COLLISION', [StringComparison]::Ordinal)) { $skipped++; continue }
        if ($HighOnly -and $r.confidence -ne 'high') { $skipped++; continue }
        $elig.Add($r)
    }
    PR-Log ("Subtitles: {0} video(s) with a known id{1}; looking up English subtitles (nothing is downloaded yet)..." -f $elig.Count, $(if ($HighOnly) { ' (high-confidence only)' } else { '' }))
    $cancelled = $false; $limit = ''; $n = 0; $nStd = 0; $nSdh = 0
    foreach ($r in $elig) {
        $n++; PR-Progress $n $elig.Count 'Looking up subtitles'
        if (PR-Cancelled) { $cancelled = $true; PR-Log 'Cancelled by user.'; break }
        $cur = $null
        if ($r.new_path -and [IO.File]::Exists([string]$r.new_path)) { $cur = [string]$r.new_path } elseif ([IO.File]::Exists([string]$r.old_path)) { $cur = [string]$r.old_path }
        if (-not $cur) { $skipped++; continue }
        $leaf = PR-Base $cur
        $it = [pscustomobject]@{ Video = $cur; Name = $leaf; Kind = [string]$r.media_type; Id = [string]$r.tmdb_id; StdStatus = 'off'; StdCands = @(); SdhStatus = 'off'; SdhCands = @(); Note = '' }
        try {
            $ex = Get-PRSubExisting $S $cur
            if ($Standard) { if ($ex.Standard) { $it.StdStatus = 'exists' } else { $it.StdStatus = 'want' } }
            if ($Sdh) { if ($ex.Sdh) { $it.SdhStatus = 'exists' } else { $it.SdhStatus = 'want' } }
            if ($it.StdStatus -ne 'want' -and $it.SdhStatus -ne 'want') { $items.Add($it); PR-Log ("[{0}/{1}] {2}: standard {3}, SDH {4}" -f $n, $elig.Count, $leaf, (PR-SubStatusText $it.StdStatus $null), (PR-SubStatusText $it.SdhStatus $null)); continue }
            $isEp = ($r.media_type -eq 'episode'); $kind = 'movie'; if ($isEp) { $kind = 'tv' }
            $se = $null
            if ($isEp) {
                $src = [string]$r.new_path; if ($src) { $se = PR-SubEpOf $src }
                if (-not $se) { $se = PR-SubEpOf ([string]$r.old_path) }
                if (-not $se) { $it.Note = 'no SxxEyy in the name'; if ($it.StdStatus -eq 'want') { $it.StdStatus = 'skipped' }; if ($it.SdhStatus -eq 'want') { $it.SdhStatus = 'skipped' }; $items.Add($it); PR-Log "[$n/$($elig.Count)] $leaf : skipped (no SxxEyy in the name)"; continue }
            }
            $rid = PR-SubResolve $S ([string]$r.tmdb_id) $kind
            if (-not $rid) { $it.Note = 'no id to search with (needs a TMDB key or TVDB key to map tvdb: ids)'; if ($it.StdStatus -eq 'want') { $it.StdStatus = 'skipped' }; if ($it.SdhStatus -eq 'want') { $it.SdhStatus = 'skipped' }; $items.Add($it); PR-Log "[$n/$($elig.Count)] $leaf : skipped ($($it.Note))"; continue }
            $sn = 0; $en = 0; if ($se) { $sn = $se.S; $en = $se.E }
            $all = PR-SubLookup $S $kind $rid.Type $rid.Id $sn $en
            $stem = (PR-SplitExt $leaf)[0]
            if ($it.StdStatus -eq 'want') { $c = PR-SubPick $all $stem $isEp 'standard' 3; $it.StdCands = @($c); if (@($c).Count -gt 0) { $it.StdStatus = 'found'; $nStd++ } else { $it.StdStatus = 'none' } }
            if ($it.SdhStatus -eq 'want') { $c = PR-SubPick $all $stem $isEp 'sdh' 3; $it.SdhCands = @($c); if (@($c).Count -gt 0) { $it.SdhStatus = 'found'; $nSdh++ } else { $it.SdhStatus = 'none' } }
            $items.Add($it)
            PR-Log ("[{0}/{1}] {2}: standard {3}, SDH {4}" -f $n, $elig.Count, $leaf, (PR-SubStatusText $it.StdStatus $it.StdCands), (PR-SubStatusText $it.SdhStatus $it.SdhCands))
        } catch {
            $m = $_.Exception.Message
            if ($m -like 'LIMIT:*') { $limit = "TSDB lookup limit reached (try again in about $([math]::Ceiling([int]($m.Substring(6)) / 60)) min)"; PR-Log $limit; break }
            $it.Note = "error: $m"; if ($it.StdStatus -eq 'want') { $it.StdStatus = 'error' }; if ($it.SdhStatus -eq 'want') { $it.SdhStatus = 'error' }
            $items.Add($it); PR-Log "[$n/$($elig.Count)] $leaf : lookup failed: $m"
        }
    }
    Save-PRSubsCache $S
    if ($S.Db) { try { Save-PRTmdbCache $S.Db } catch { } }
    PR-Progress 1 1 'Done'
    PR-Log "Subtitle lookup finished: $nStd standard and $nSdh SDH subtitle(s) can be downloaded for $($items.Count) video(s); $skipped row(s) skipped (not high-confidence, duplicate, or file missing). Lookups: $($S.Lookups)."
    return @{ Items = $items.ToArray(); Std = $nStd; Sdh = $nSdh; Skipped = $skipped; Cancelled = $cancelled; Limit = $limit }
}
function Get-PRSubsEstimate([int]$Count) {
    # human text for how long $Count downloads take (TSDB allows roughly 200 downloads per hour per IP)
    if ($Count -le 0) { return 'nothing to download' }
    if ($Count -le 200) { $m = [math]::Max(1, [math]::Ceiling($Count * 1.5 / 60)); if ($m -le 1) { return 'about a minute' }; return "about $m minutes" }
    $h = [math]::Ceiling($Count / 200.0)
    return "about $h hour(s): TSDB allows about 200 downloads per hour, so the run stops when that limit is reached and the next run continues where it left off"
}

# ----- download -----
function Invoke-PRSubsDownload {
    # downloads what the plan found (first valid of up to 3 candidates per part), writes <stem>.en.srt / <stem>.en.sdh.srt, logs each attempt to a CSV
    param($Plan, $S, [string]$LogPath)
    $log = New-Object System.Collections.Generic.List[object]
    $cols = @('downloaded_at', 'video_path', 'subtitle_path', 'kind', 'subtitle_id', 'release_name', 'cues', 'result')
    $nStd = 0; $nSdh = 0; $rej = 0; $fail = 0; $skip = 0; $stopMsg = ''; $cancelled = $false; $n = 0
    $todo = @($Plan.Items | Where-Object { $_.StdStatus -eq 'found' -or $_.SdhStatus -eq 'found' })
    foreach ($it in $todo) {
        $n++; PR-Progress $n $todo.Count 'Downloading subtitles'
        if (PR-Cancelled) { $cancelled = $true; PR-Log 'Cancelled by user.'; break }
        if ($stopMsg) { break }
        $parts = @(@{ Kind = 'standard'; Status = $it.StdStatus; Cands = @($it.StdCands) }, @{ Kind = 'sdh'; Status = $it.SdhStatus; Cands = @($it.SdhCands) })
        foreach ($p in $parts) {
            if ($p.Status -ne 'found' -or $stopMsg) { continue }
            $target = Get-PRSubTarget $it.Video $p.Kind
            if ([IO.File]::Exists($target)) { PR-Log "SKIP exists: $target"; $skip++; continue }
            $done = $false; $tries = 0
            foreach ($c in @($p.Cands | Select-Object -First 3)) {
                if ($done -or $stopMsg) { break }
                $tries++; $res = $null
                try { $res = PR-SubFetch $S $c }
                catch {
                    $m = $_.Exception.Message
                    if ($m -like 'LIMIT:*') {
                        $secs = 0; [void][int]::TryParse($m.Substring(6), [ref]$secs)
                        $when = 'later'; if ($secs -gt 0) { $when = "in about $([math]::Ceiling($secs / 60.0)) minute(s)" }
                        $stopMsg = "Download limit reached (HTTP 429). Stopped cleanly; run Get subtitles again $when to continue - subtitles already downloaded are skipped."
                        PR-Log $stopMsg; break
                    }
                    if ($m -eq 'NOTFOUND') { PR-Log "candidate $($c.Id) is gone; trying the next"; continue }
                    $fail++; PR-Log "FAILED $($it.Name) ($($p.Kind)) candidate $($c.Id): $m"
                    $log.Add([pscustomobject][ordered]@{ downloaded_at = (Get-Date -Format s); video_path = $it.Video; subtitle_path = $target; kind = $p.Kind; subtitle_id = $c.Id; release_name = $c.Name; cues = 0; result = "failed: $m" })
                    continue
                }
                if (-not $res.Ok) {
                    $rej++; PR-Log "rejected ($($res.Why)): $($c.Name) for $($it.Name)"
                    $log.Add([pscustomobject][ordered]@{ downloaded_at = (Get-Date -Format s); video_path = $it.Video; subtitle_path = $target; kind = $p.Kind; subtitle_id = $c.Id; release_name = $c.Name; cues = $res.Cues; result = "rejected: $($res.Why)" })
                    continue
                }
                try {
                    $tmp = $target + '.part'
                    [IO.File]::WriteAllText($tmp, [string]$res.Text, (New-Object Text.UTF8Encoding($false)))
                    [IO.File]::Move($tmp, $target)   # never overwrites
                    $done = $true
                    if ($p.Kind -eq 'sdh') { $nSdh++ } else { $nStd++ }
                    PR-Log "saved $($p.Kind): $target ($($res.Cues) cues)"
                    $log.Add([pscustomobject][ordered]@{ downloaded_at = (Get-Date -Format s); video_path = $it.Video; subtitle_path = $target; kind = $p.Kind; subtitle_id = $c.Id; release_name = $c.Name; cues = $res.Cues; result = 'downloaded' })
                } catch {
                    $fail++; PR-Log "FAILED to write $target : $($_.Exception.Message)"
                    try { if ([IO.File]::Exists($target + '.part')) { [IO.File]::Delete($target + '.part') } } catch { }
                }
            }
            if (-not $done -and -not $stopMsg -and $tries -gt 0) { PR-Log "no usable $($p.Kind) subtitle for $($it.Name)" }
            if ($log.Count -le 300 -or ($log.Count % 20) -eq 0) { try { Export-PRCsv $log $LogPath $cols } catch { } }
            if (-not $stopMsg -and $S.DlRemaining -eq 0) {
                $secs = [int]$S.DlReset; $when = 'later'; if ($secs -gt 0) { $when = "in about $([math]::Ceiling($secs / 60.0)) minute(s)" }
                $stopMsg = "Reached the download limit (about 200 per hour). Stopped cleanly; run Get subtitles again $when to continue - subtitles already downloaded are skipped."
                PR-Log $stopMsg
            }
        }
    }
    try { Export-PRCsv $log $LogPath $cols } catch { }
    PR-Log "Subtitles done: $nStd standard, $nSdh SDH downloaded; $rej rejected, $fail failed, $skip already existed. Log: $LogPath"
    return @{ Standard = $nStd; Sdh = $nSdh; Rejected = $rej; Failed = $fail; Skipped = $skip; Stopped = $stopMsg; Cancelled = $cancelled; Log = $LogPath }
}
