# Renamr engine - faithful port of plan.py + apply/undo logic. Windows PowerShell 5.1 and PowerShell 7 compatible.
# No UI code here. The GUI (Renamr.ps1) loads this into a background runspace.
# Paths are always Windows-style (backslash) strings; path helpers below do not depend on the host OS.

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
    if ($path -like '/search/*') {
        $res = @(); foreach ($r in @($data.results)) { if ($null -eq $r) { continue }
            $o = [ordered]@{ id = $r.id; popularity = $r.popularity }
            foreach ($f in 'title','original_title','release_date','name','original_name','first_air_date') { if ($null -ne $r.$f) { $o[$f] = $r.$f } }
            $res += [pscustomobject]$o }
        return [pscustomobject]@{ results = $res }
    }
    $eps = @(); foreach ($e in @($data.episodes)) { if ($null -ne $e) { $eps += [pscustomobject]@{ episode_number = $e.episode_number; name = $e.name } } }
    return [pscustomobject]@{ episodes = $eps }
}
function New-PRTmdb([string]$Key, [string]$CachePath, [string]$TvdbKey = '', [string]$TvdbPin = '', [string]$Source = 'Movies: TMDB, TV: TVDB') {
    $cache = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    if ($CachePath -and (Test-Path -LiteralPath $CachePath)) {
        try {
            # stored as [{"k":key,"v":value},...] because PS 5.1 ConvertFrom-Json rejects keys differing only by case
            $obj = [IO.File]::ReadAllText($CachePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($e in @($obj)) { if ($null -ne $e) { $cache[[string]$e.k] = $e.v } }
        } catch { PR-Log "Cache unreadable, starting fresh: $($_.Exception.Message)" }
    }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    return @{ Key = $Key; CachePath = $CachePath; Cache = $cache; Last = [Diagnostics.Stopwatch]::StartNew(); Dirty = 0; Calls = 0; Source = $Source; Tvdb = @{ Key = $TvdbKey; Pin = $TvdbPin; Token = ''; Stamp = [Diagnostics.Stopwatch]::StartNew() } }
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
    if (-not $db.Key) { throw "TMDB key missing and $ck not in cache" }
    $q = @{}; foreach ($k in $clean.Keys) { $q[$k] = $clean[$k] }; $q['api_key'] = $db.Key
    $url = 'https://api.themoviedb.org/3' + $path + '?' + (PR-UrlEncode $q)
    $data = $null; $ok = $false
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $wait = 30 - $db.Last.ElapsedMilliseconds; if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }   # ~30 req/s
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
    return (PR-TmdbGet $db $path $params)
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
    $best = $null; $sameName = @{}
    $ys = @($null); if ($year) { $ys = @($year, $null) }
    foreach ($y in $ys) {
        $resp = PR-Api $db $provider '/search/movie' @{ query = $title; primary_release_year = $y; include_adult = 'false' }
        $res = @(); if ($resp) { $res = @($resp.results) }
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
            if ($ry -and ($null -eq $best -or $score -gt $best.Score)) { $best = @{ Score = $score; R = $r; S = $s; Ry = $ry; Yok = $yok } }
        }
        if ($best -and $best.S -ge 0.85 -and $best.Yok) { break }
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
    return @{ Provider = $provider; Id = $r.id; Title = (PR-Safe $r.title); Year = $ry; Conf = $conf; Note = $note; Ambig = $ambig }
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
            if ($ry -and ($null -eq $best -or $score -gt $best.Score)) { $best = @{ Score = $score; R = $r; S = $s; Ry = $ry } }
        }
        if ($best) { break }
    }
    if ($null -eq $best -or $best.S -lt 0.6) { return $null }
    return @{ Provider = $provider; Id = $best.R.id; Name = (PR-Safe $best.R.name); Year = $best.Ry; Sim = $best.S }
}
function PR-MatchMovie($db, [string]$title, $year) {
    # try providers in order; first high-confidence match wins, else the best low-confidence one
    $keep = $null
    foreach ($pv in (PR-Providers $db)) {
        $m = $null
        try { $m = PR-MatchMovieOne $db $pv $title $year } catch { if ($keep -or $pv -eq 'tvdb') { PR-Log "[$pv] lookup failed for `"$title`": $($_.Exception.Message)"; continue } else { throw } }
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
        try { $m = PR-MatchShowOne $db $pv $name $year } catch { if ($pv -eq 'tvdb') { PR-Log "[tvdb] lookup failed for `"$name`": $($_.Exception.Message)"; continue } else { throw } }
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
function PR-NewRow($p) { return [pscustomobject][ordered]@{ old_path = $p; new_path = ''; media_type = ''; tmdb_id = ''; confidence = ''; note = '' } }

# ---------- planner: port of plan.py main() ----------
function New-PRPlan {
    param([string[]]$Paths, [string]$MoviesRoot, [string]$SeriesRoot, $Db, [bool]$ProbeReal = $true, [bool]$FolderLoose = $true)
    $mroot = ''; if ($MoviesRoot) { $mroot = $MoviesRoot.TrimEnd('\') }
    $sroot = ''; if ($SeriesRoot) { $sroot = $SeriesRoot.TrimEnd('\') }
    $paths = @($Paths | ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } | Where-Object { $_ })
    $excluded = 0; $ok = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) { if ($script:PR_SKIP.IsMatch($p)) { $excluded++ } else { $ok.Add($p) } }
    $videos = New-Object System.Collections.Generic.List[string]; $sidecars = New-Object System.Collections.Generic.List[string]
    foreach ($p in $ok) { $e = (PR-SplitExt $p)[1].ToLowerInvariant(); if ($script:PR_VIDEO -contains $e) { $videos.Add($p) } elseif ($script:PR_SIDECAR -contains $e) { $sidecars.Add($p) } }
    PR-Log ("Checked {0} files: {1} videos, {2} subtitle and extra files{3}{4}." -f $paths.Count, $videos.Count, $sidecars.Count, $(if ($excluded) { ", $excluded skipped" } else { "" }), $(if (($ok.Count - $videos.Count - $sidecars.Count) -gt 0) { ", $($ok.Count - $videos.Count - $sidecars.Count) other files left alone" } else { "" }))
    $rows = New-Object System.Collections.Generic.List[object]
    $shows = @{}; $seasons = @{}; $ambig = @{}
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
                $key2 = (PR-Norm $cand.Title) + '|' + $cand.Year
                if (-not $shows.ContainsKey($key2)) {
                    $shows[$key2] = PR-MatchShow $Db $cand.Title $cand.Year
                    if (-not $shows[$key2] -and $rel.Count -gt 1) { $f = PR-ParseShow $rel[0]; $shows[$key2] = PR-MatchShow $Db $f.Title $f.Year }
                }
                $sh = $shows[$key2]
                if (-not $sh) { $row.note = "unmatched: no TMDB show for `"$($cand.Title)`""; $rows.Add($row); continue }
                $tid = $sh.Id; $sname = PR-StripYear ([string]$sh.Name); $sy = $sh.Year; $ssim = $sh.Sim
                $prov = [string]$sh.Provider; if (-not $prov) { $prov = 'tmdb' }
                $eps = PR-Season $Db $seasons $tid $s $prov
                $ftitle = (PR-CleanTokens $stem.Substring($mend)) -join ' '
                $notes = New-Object System.Collections.Generic.List[string]
                $notes.Add("show `"$sname`" sim=$(PR-F2 $ssim)"); if ($prov -eq 'tvdb') { $notes.Add('source: TVDB') }; foreach ($x in $extra) { $notes.Add($x) }
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
                $mm = $null; if ($pm.Title) { $mm = PR-MatchMovie $Db $pm.Title $pm.Year }
                if (-not $mm) { $yr = 'None'; if ($pm.Year) { $yr = $pm.Year }; $row.note = "unmatched: no TMDB movie for `"$($pm.Title)`" ($yr)"; $rows.Add($row); continue }
                $base = PR-Safe "$(PR-StripYear ([string]$mm.Title)) ($($mm.Year))"
                if ((-not $FolderLoose) -and ((PR-Dir $p).TrimEnd('\').ToLowerInvariant() -eq $mroot.ToLowerInvariant())) { $row.new_path = PR-Join $mroot ($base + $ext) } else { $row.new_path = PR-Join $mroot $base ($base + $ext) }   # option off: a movie loose in the library root is only renamed, not put into its own folder
                $row.tmdb_id = $(if ($mm.Provider -eq 'tvdb') { 'tvdb:' + [string]$mm.Id } else { [string]$mm.Id }); $row.confidence = $mm.Conf; $row.note = $mm.Note
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
    foreach ($p in $paths) { [void]$existing.Add($p.ToLowerInvariant()) }
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
        if ($r.new_path -ceq $r.old_path) { $r.new_path = ''; $r.note = 'already correctly named; skipped'; continue }
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
    $sn = 0
    foreach ($item in $sorted) {
        $sn++; if ($sn % 50 -eq 0) { PR-Progress $sn $sorted.Count 'Matching subtitles' }
        $p = $item.P; $d = PR-Dir $p; $fn = PR-Base $p; $parts = $d.Split('\')
        $row = PR-NewRow $p; $row.media_type = 'sidecar'
        $v = $null; $suffix = $null
        $cands = @(); if ($vidByDir.ContainsKey($d.ToLowerInvariant())) { $cands = @($vidByDir[$d.ToLowerInvariant()] | Where-Object { $fn.ToLowerInvariant().StartsWith((PR-SplitExt (PR-Base $_.old_path))[0].ToLowerInvariant(), [StringComparison]::Ordinal) }) }
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
                $v = $pv[0]; $ls = PR-LangSuffix (PR-SplitExt $fn)[0]
                if ($ls) { $suffix = $ls + (PR-SplitExt $fn)[1].ToLowerInvariant() } else { $row.note = 'sidecar: unknown language in name; left in place' }
            }
        }
        if ($v -and $suffix) {
            $base = $v.new_path; if (-not $base) { $base = $v.old_path }
            $np = (PR-SplitExt $base)[0] + $suffix
            $row.tmdb_id = $v.tmdb_id; $row.confidence = $v.confidence; if (-not $row.confidence) { $row.confidence = 'high' }
            if ($taken.ContainsKey($np.ToLowerInvariant()) -or ($existing.Contains($np.ToLowerInvariant()) -and $np.ToLowerInvariant() -ne $p.ToLowerInvariant())) { $row.note = 'DUPLICATE sidecar target (same language already placed); left in place' }
            elseif ($np -ceq $p) { $row.note = 'sidecar already correctly named' }
            else {
                $row.new_path = $np; $taken[$np.ToLowerInvariant()] = $p
                $row.note = 'sidecar of ' + (PR-Base $v.old_path); if (-not $v.new_path) { $row.note += ' (video not moved)' }
            }
        } elseif (-not $row.note) { $row.note = 'sidecar: no matching video; left in place' }
        $rows.Add($row)
    }
    PR-Progress 1 1 'Done'
    return ,$rows.ToArray()
}
function PR-EpCode($em) {
    if ($em.Groups[1].Success) { return "$([int]$em.Groups[1].Value)|$([int]$em.Groups[2].Value)" }
    return "$([int]$em.Groups[4].Value)|$([int]$em.Groups[5].Value)"
}
function PR-EpCodeOf([string]$path) { $mm = $script:PR_EP.Match((PR-SplitExt (PR-Base $path))[0]); if ($mm.Success) { return (PR-EpCode $mm) }; return $null }
function PR-LangSuffix([string]$name) {
    $words = @([regex]::Matches($name.ToLowerInvariant(), '[a-z]+') | ForEach-Object { $_.Value })
    $code = $null; foreach ($w in $words) { if ($script:PR_LANG.ContainsKey($w)) { $code = $script:PR_LANG[$w]; break } }
    if (-not $code) { return $null }
    $flags = @(); foreach ($f in 'forced', 'sdh') { if ($words -contains $f) { $flags += $f } }
    if ($words -contains 'hi' -and -not ($words -contains 'sdh')) { $flags += 'sdh' }
    return '.' + ((@($code) + $flags) -join '.')
}
function Get-PRSummary($rows) {
    $t = 0; $h = 0; $l = 0; $s = 0; $a = 0
    foreach ($r in $rows) {
        $t++
        if ($r.new_path) { if ($r.confidence -eq 'high') { $h++ } elseif ($r.confidence -eq 'low') { $l++ } } else { $s++ }
        if ($r.note -like '*already correctly named*') { $a++ }
    }
    return "Result: $h ready to rename (high confidence), $l to review (low confidence), $s left as they are (unmatched or no change needed; $a already correctly named), $t total."
}

# ---------- file system scan ----------
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
function Export-PRPlan($rows, [string]$path) { Export-PRCsv $rows $path @('old_path','new_path','media_type','tmdb_id','confidence','note') }

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
function Invoke-PRApply {
    param($Rows, [switch]$HighOnly, [string]$UndoLog)
    $todo = @($Rows | Where-Object { $_.new_path -and (-not $HighOnly -or $_.confidence -eq 'high') })
    $log = New-Object System.Collections.Generic.List[object]
    $moved = 0; $skipped = 0; $failed = 0; $n = 0; $stopped = $false
    foreach ($r in $todo) {
        $n++; PR-Progress $n $todo.Count 'Moving files'
        if (PR-Cancelled) { PR-Log 'Stopped by user.'; $stopped = $true; break }
        $old = $r.old_path; $new = $r.new_path
        try {
            if (-not [IO.File]::Exists($old)) { PR-Log "SKIP missing source: $old"; $skipped++; continue }
            $caseOnly = ($old.ToLowerInvariant() -eq $new.ToLowerInvariant())
            if (-not $caseOnly -and ([IO.File]::Exists($new) -or [IO.Directory]::Exists($new))) { PR-Log "SKIP target exists: $new"; $skipped++; continue }
            $dir = PR-NativeDir $new; $created = ''
            if (-not [IO.Directory]::Exists($dir)) {
                $created = $dir; $up = PR-NativeDir $dir
                while ($up -and -not [IO.Directory]::Exists($up)) { $created = $up; $up = PR-NativeDir $up }
                [void][IO.Directory]::CreateDirectory($dir)
            }
            PR-MoveKeepTimes $old $new $caseOnly   # never overwrites; keeps the file's timestamps
            $log.Add([pscustomobject][ordered]@{ moved_at = (Get-Date -Format s); old_path = $old; new_path = $new; created_dir = $created })
            $moved++
            Export-PRCsv $log $UndoLog @('moved_at','old_path','new_path','created_dir')   # incremental so a crash keeps a usable log
        } catch { PR-Log "FAILED $old : $($_.Exception.Message)"; $failed++ }
    }
    $msg = "Moved $moved, skipped $skipped, failed $failed."; if ($stopped) { $msg = "Stopped. " + $msg }; if ($moved) { $msg += " Undo log: $UndoLog" }
    PR-Log $msg
    return @{ Moved = $moved; Skipped = $skipped; Failed = $failed; Log = $UndoLog; Cancelled = $stopped }
}
function Invoke-PRUndo {
    param([string]$UndoLog, [switch]$WhatIf)
    $rows = @(Import-Csv -LiteralPath $UndoLog -Encoding UTF8); [Array]::Reverse($rows)
    $ok = 0; $skip = 0; $n = 0
    foreach ($r in $rows) {
        $n++; PR-Progress $n $rows.Count 'Undoing'
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
    PR-Log "Undo: restored $ok, skipped $skip."
    return @{ Restored = $ok; Skipped = $skip }
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
