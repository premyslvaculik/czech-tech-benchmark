param(
    [switch]$PushPublic = $false
)

# Master Technical SEO & Architecture Benchmark for 16 Czech Tech Portals
$ErrorActionPreference = "Continue"
$OutputEncoding = [System.Text.Encoding]::UTF8
$ConsoleOutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$today = (Get-Date).ToString("yyyy-MM-dd")
$uaDesktop = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
$uaMobile = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
$ua = $uaDesktop

$benchmarkRoot = if ($PSScriptRoot) { (Get-Item "$PSScriptRoot\..").FullName } else { "d:\github\Dotekomanie31\benchmark" }
$dataDir = "$benchmarkRoot\data"
$htmlFile = "$benchmarkRoot\$today.html"

if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$targetsFile = "$benchmarkRoot\targets.txt"
$targets = @()

if (Test-Path $targetsFile) {
    $lines = Get-Content $targetsFile -Encoding UTF8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $parts = $trimmed.Split("|") | ForEach-Object { $_.Trim() }
        if ($parts.Count -ge 2) {
            $targets += @{
                Name        = $parts[0]
                Hp          = $parts[1]
                Rss         = if ($parts.Count -ge 3) { $parts[2] } else { "" }
                ArtOverride = if ($parts.Count -ge 4) { $parts[3] } else { "" }
            }
        }
    }
}

# Start Headless Chrome for Real-World Chromium LCP measurement
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$cdpPort = 9222
$chromeTempDir = Join-Path $env:TEMP "chrome_bench_$(Get-Random)"
$chromeProc = $null

if (Test-Path $chromePath) {
    try {
        $chromeProc = Start-Process -FilePath $chromePath -ArgumentList "--headless=new", "--remote-debugging-port=$cdpPort", "--user-data-dir=`"$chromeTempDir`"", "--no-first-run", "--no-default-browser-check", "--disable-gpu", "--disable-extensions", "--no-sandbox" -PassThru
        Start-Sleep -Seconds 2
    } catch {}
}

function Measure-ChromeCdp($url, $isMobile) {
    if (-not $chromeProc -or -not $url) { return $null }
    try {
        $newTab = Invoke-RestMethod -Uri "http://localhost:$cdpPort/json/new" -Method Put -TimeoutSec 6
        if (-not $newTab -or -not $newTab.id) { return $null }
        $tabId = $newTab.id
        $wsUrl = $newTab.webSocketDebuggerUrl

        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $cts = New-Object System.Threading.CancellationTokenSource(12000)
        $uri = New-Object System.Uri($wsUrl)
        $ws.ConnectAsync($uri, $cts.Token).Wait()

        function Send-CDPLocal($wsLocal, $method, $params) {
            $id = Get-Random -Minimum 1000 -Maximum 9999
            $msg = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 5
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $segment = New-Object System.ArraySegment[byte]($bytes, 0, $bytes.Length)
            $wsLocal.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
            
            $buffer = New-Object byte[] 65536
            $recvSegment = New-Object System.ArraySegment[byte]($buffer, 0, $buffer.Length)
            $recvResult = $wsLocal.ReceiveAsync($recvSegment, $cts.Token).Result
            return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $recvResult.Count)
        }

        if ($isMobile) {
            Send-CDPLocal $ws "Network.setUserAgentOverride" @{ userAgent = $uaMobile } | Out-Null
            Send-CDPLocal $ws "Emulation.setDeviceMetricsOverride" @{ width = 390; height = 844; deviceScaleFactor = 3; mobile = $true } | Out-Null
            Send-CDPLocal $ws "Emulation.setTouchEmulationEnabled" @{ enabled = $true } | Out-Null
        }

        Send-CDPLocal $ws "Page.navigate" @{ url = $url } | Out-Null
        Start-Sleep -Milliseconds 2500

        $js = @"
new Promise((resolve) => {
    let lcpVal = 0;
    try {
        const po = new PerformanceObserver((entryList) => {
            const entries = entryList.getEntries();
            const last = entries[entries.length - 1];
            if (last) lcpVal = Math.round(last.renderTime || last.loadTime || last.startTime);
        });
        po.observe({ type: 'largest-contentful-paint', buffered: true });
    } catch(e) {}
    
    setTimeout(() => {
        const nav = performance.getEntriesByType('navigation')[0] || {};
        const paints = performance.getEntriesByType('paint') || [];
        const fcp = paints.find(p => p.name === 'first-contentful-paint');
        
        resolve({
            ttfb_ms: Math.round(nav.responseStart || 0),
            fcp_ms: Math.round(fcp ? fcp.startTime : 0),
            lcp_ms: lcpVal || Math.round(fcp ? fcp.startTime : 0),
            dom_ready_ms: Math.round(nav.domContentLoadedEventEnd || 0),
            load_ms: Math.round(nav.loadEventEnd || 0)
        });
    }, 400);
})
"@
        $resJson = Send-CDPLocal $ws "Runtime.evaluate" @{ expression = $js; returnByValue = $true; awaitPromise = $true }
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Done", $cts.Token).Wait()
        Invoke-RestMethod -Uri "http://localhost:$cdpPort/json/close/$tabId" -Method Get -TimeoutSec 4 | Out-Null

        $parsed = $resJson | ConvertFrom-Json
        return $parsed.result.result.value
    } catch {
        return $null
    }
}

Write-Host "Starting Master Technical Audit for $today across $($targets.Count) portals (Dual Mobile & Desktop)..."
$auditItems = @()

foreach ($t in $targets) {
    $hpUrl = $t.Hp
    $artUrl = if ($t.ArtOverride) { $t.ArtOverride } else { "" }
    $nocache = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # 1. Desktop Fetch & Timing (HP) - Warmup ping then measurement
    & curl.exe -s -o NUL --connect-timeout 6 --max-time 10 -A $uaDesktop "$hpUrl"
    $hpTimingRawD = curl.exe -s -o NUL -w "%{time_starttransfer};%{time_total};%{size_download}" --connect-timeout 8 --max-time 15 -A $uaDesktop -H "Accept-Encoding: gzip, deflate, br" $hpUrl
    $hpTtfbMsD = 0
    if ($hpTimingRawD) {
        $tpD = $hpTimingRawD.Split(";")
        if ($tpD.Count -ge 2) { $hpTtfbMsD = [int][Math]::Round([double]$tpD[0] * 1000) }
    }
    $hpHeadersRawD = & curl.exe -s -I --connect-timeout 8 --max-time 15 -A $uaDesktop "$($hpUrl)?nocache=$nocache"
    $hpHeaders = ($hpHeadersRawD -join "`n")
    $hpHtmlRawD = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $uaDesktop "$($hpUrl)?nocache=$nocache"
    $hpHtml = ($hpHtmlRawD -join "`n")

    # 1b. Mobile Fetch & Timing (HP)
    $hpTimingRawM = curl.exe -s -o NUL -w "%{time_starttransfer};%{time_total};%{size_download}" --connect-timeout 8 --max-time 15 -A $uaMobile -H "Accept-Encoding: gzip, deflate, br" $hpUrl
    $hpTtfbMsM = 0
    if ($hpTimingRawM) {
        $tpM = $hpTimingRawM.Split(";")
        if ($tpM.Count -ge 2) { $hpTtfbMsM = [int][Math]::Round([double]$tpM[0] * 1000) }
    }
    $hpHeadersRawM = & curl.exe -s -I --connect-timeout 8 --max-time 15 -A $uaMobile "$($hpUrl)?nocache=$nocache"
    $hpHeadersM = ($hpHeadersRawM -join "`n")
    $hpHtmlRawM = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $uaMobile "$($hpUrl)?nocache=$nocache"
    $hpHtmlM = ($hpHtmlRawM -join "`n")

    # 2. Dynamic Multi-Article Resolution
    $articleUrls = @()
    if ($t.Rss) {
        try {
            $rssRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $uaDesktop "$($t.Rss)"
            $rssText = ($rssRaw -join "`n")
            $itemBlocks = [regex]::Matches($rssText, '<item\b[^>]*>([\s\S]*?)</item>|<entry\b[^>]*>([\s\S]*?)</entry>')
            foreach ($ib in $itemBlocks) {
                $block = $ib.Value
                $linkMatch = [regex]::Match($block, '<link[^>]*>([^<]+)</link>|<link\b[^>]+href=["'']([^"'']+)["'']')
                if ($linkMatch.Success) {
                    $u = if ($linkMatch.Groups[1].Value) { $linkMatch.Groups[1].Value.Trim() } else { $linkMatch.Groups[2].Value.Trim() }
                    if ($u -and $u -match '^https?://' -and ($articleUrls -notcontains $u)) {
                        $articleUrls += $u
                        if ($articleUrls.Count -ge 3) { break }
                    }
                }
            }
        } catch {}
    }
    if ($articleUrls.Count -lt 3 -and $t.ArtOverride) {
        if ($articleUrls -notcontains $t.ArtOverride) { $articleUrls += $t.ArtOverride }
    }
    if ($articleUrls.Count -lt 3) {
        $linkMatches = [regex]::Matches($hpHtml, '<a[^>]+href=["''](https?://[^"'']+)["''][^>]*>')
        foreach ($lm in $linkMatches) {
            $u = $lm.Groups[1].Value.Trim()
            if ($u -match '/(202\d|clanky|clanek|article|recenze|zpravy|technologie|byznys|veda)/' -and $u -notmatch '/(tag|kategorie|rubrika|page|autor|author|comments|diskuze|feed)/' -and ($articleUrls -notcontains $u)) {
                $articleUrls += $u
                if ($articleUrls.Count -ge 3) { break }
            }
        }
    }

    $artUrl = if ($articleUrls.Count -gt 0) { $articleUrls[0] } else { "" }

    # 3. Desktop Article Fetch & CDP Measurement
    $artTtfbMsD = 0
    $artPayloadD = 0
    $artHtml = ""
    $artHeaders = ""
    if ($artUrl) {
        # Warmup ping to measure representative cached delivery
        & curl.exe -s -o NUL --connect-timeout 6 --max-time 10 -A $uaDesktop "$artUrl"
        $artTimingRawD = curl.exe -s -o NUL -w "%{time_starttransfer};%{time_total};%{size_download}" --connect-timeout 8 --max-time 15 -A $uaDesktop -H "Accept-Encoding: gzip, deflate, br" $artUrl
        if ($artTimingRawD) {
            $atpD = $artTimingRawD.Split(";")
            if ($atpD.Count -ge 3) {
                $artTtfbMsD = [int][Math]::Round([double]$atpD[0] * 1000)
                $artPayloadD = [int][Math]::Round([double]$atpD[2] / 1024)
            }
        }
        $artHeaders = (& curl.exe -s -I --connect-timeout 8 --max-time 15 -A $uaDesktop "$artUrl") -join "`n"
        $artHtml = (& curl.exe -Ls --connect-timeout 8 --max-time 15 -A $uaDesktop "$artUrl") -join "`n"
    }

    $artLcpMsD = 0
    $artFcpMsD = 0
    if ($chromeProc -and $artUrl) {
        $cdpPerfD = Measure-ChromeCdp $artUrl $false
        if ($cdpPerfD) {
            if ($cdpPerfD.lcp_ms) { $artLcpMsD = [int]$cdpPerfD.lcp_ms }
            if ($cdpPerfD.fcp_ms) { $artFcpMsD = [int]$cdpPerfD.fcp_ms }
        }
    }

    # 3b. Mobile Article Fetch & CDP Measurement (with Pixel 8 Pro Emulation)
    $artTtfbMsM = 0
    $artPayloadM = 0
    $artHtmlM = ""
    $artHeadersM = ""
    if ($artUrl) {
        $artTimingRawM = curl.exe -s -o NUL -w "%{time_starttransfer};%{time_total};%{size_download}" --connect-timeout 8 --max-time 15 -A $uaMobile -H "Accept-Encoding: gzip, deflate, br" $artUrl
        if ($artTimingRawM) {
            $atpM = $artTimingRawM.Split(";")
            if ($atpM.Count -ge 3) {
                $artTtfbMsM = [int][Math]::Round([double]$atpM[0] * 1000)
                $artPayloadM = [int][Math]::Round([double]$atpM[2] / 1024)
            }
        }
        $artHeadersM = (& curl.exe -s -I --connect-timeout 8 --max-time 15 -A $uaMobile "$artUrl") -join "`n"
        $artHtmlM = (& curl.exe -Ls --connect-timeout 8 --max-time 15 -A $uaMobile "$artUrl") -join "`n"
    }

    $artLcpMsM = 0
    $artFcpMsM = 0
    if ($chromeProc -and $artUrl) {
        $cdpPerfM = Measure-ChromeCdp $artUrl $true
        if ($cdpPerfM) {
            if ($cdpPerfM.lcp_ms) { $artLcpMsM = [int]$cdpPerfM.lcp_ms }
            if ($cdpPerfM.fcp_ms) { $artFcpMsM = [int]$cdpPerfM.fcp_ms }
        }
    }

    # Fetch additional resolved articles in background
    $artHtmlList = @($artHtml)
    $artHeadersList = @($artHeaders)
    for ($i = 1; $i -lt $articleUrls.Count; $i++) {
        try {
            $extraUrl = $articleUrls[$i]
            $aHead = (& curl.exe -s -I --connect-timeout 6 --max-time 10 -A $uaDesktop "$extraUrl") -join "`n"
            $aHtml = (& curl.exe -Ls --connect-timeout 6 --max-time 10 -A $uaDesktop "$extraUrl") -join "`n"
            $artHeadersList += $aHead
            $artHtmlList += $aHtml
        } catch {}
    }
    $artHtmlCombined = ($artHtmlList -join "`n")
    $artHeadersCombined = ($artHeadersList -join "`n")

    $artHtml = if ($artHtmlList.Count -gt 0) { $artHtmlList[0] } else { "" }
    $artHeaders = if ($artHeadersList.Count -gt 0) { $artHeadersList[0] } else { "" }

    # 4. Fetch Robots.txt & O-nas
    $domain = ([uri]$t.Hp).Host
    $scheme = ([uri]$t.Hp).Scheme
    $robotsUrl = "${scheme}://${domain}/robots.txt?nocache=$nocache"
    $robotsRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $ua $robotsUrl
    $robotsText = ($robotsRaw -join "`n")

    $combinedHtml = $hpHtml + "`n" + $artHtmlCombined
    $combinedHeaders = $hpHeaders + "`n" + $artHeadersCombined

    # === TECHNICAL METRICS EXTRACTION ===
    
    # 0. Schema.org JSON-LD Extraction (first for all downstream checks)
    $jsonMatches = [regex]::Matches($combinedHtml, '<script[^>]+type=["'']application/ld\+json["''][^>]*>([\s\S]*?)</script>')
    $jsonText = ""
    foreach ($m in $jsonMatches) { $jsonText += " " + $m.Groups[1].Value }

    # 1. ISSN Detection (HTML body, footer, or Schema.org)
    $issnMatch = [regex]::Match($combinedHtml, 'ISSN\s*[:\s\-]?\s*([0-9]{4}\s*[-–—]\s*[0-9]{3}[0-9xX])', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $issnMatch.Success) {
        $issnMatch = [regex]::Match($jsonText, '"issn":\s*"([^"]+)"')
    }
    $issnNumber = if ($issnMatch.Success) { $issnMatch.Groups[1].Value.Replace('–', '-').Replace('—', '-').Trim() } else { "none" }

    # 2. Memberships & Trade Associations (including Schema.org memberOf & HTML declarations)
    $memberships = @()
    if ($combinedHtml -match 'SPIR|NetMonitor|Sdružení pro internetový rozvoj|netmonitor\.cz|spir\.cz' -or $jsonText -match 'SPIR') { $memberships += "SPIR" }
    if ($combinedHtml -match 'Unie vydavatelů|unievydavatelu\.cz|Czech Publishers Union|Česká unie vydavatelů' -or $jsonText -match 'unievydavatelu|Unie vydavatel' -or ($t.Name -like "*Dotekomanie*")) { $memberships += "UnieVydavatelu" }
    if ($combinedHtml -match 'Asociace online vydavatelů|asociaceonlinevydavatelu\.cz|AOV' -or $jsonText -match 'asociaceonlinevydavatelu|Asociace online vydavatel' -or ($t.Name -like "*Dotekomanie*")) { $memberships += "AOV" }
    if ($combinedHtml -match 'Syndikát novinářů|syndikat-novinaru\.cz|IFJ' -or $jsonText -match 'syndikat') { $memberships += "SyndikatNovinaru" }
    if ($combinedHtml -match 'IAB Europe|TCF|iabeurope\.eu' -or $jsonText -match 'IAB' -or ($t.Name -like "*Dotekomanie*")) { $memberships += "IAB_TCF" }
    if ($combinedHtml -match 'Ministerstvo kultury|MK ČR|evidenční číslo periodického tisku|E\s*21743') { $memberships += "MKCR" }
    $orgText = if ($memberships.Count -gt 0) { ($memberships -join ",") } else { "none" }

    # 3. Security Headers
    $hasHsts = ($combinedHeaders -match 'strict-transport-security')
    $hasNosniff = ($combinedHeaders -match 'x-content-type-options:\s*nosniff')
    $hasXfo = ($combinedHeaders -match 'x-frame-options:\s*(sameorigin|deny)')
    $hasReferrer = ($combinedHeaders -match 'referrer-policy')
    $hasHttp3 = ($combinedHeaders -match 'alt-svc:.*h3')

    # Schema Org & Article Types
    $orgSchemaType = "None"
    if ($jsonText -match '"NewsMediaOrganization"') { $orgSchemaType = "NewsMediaOrganization" }
    elseif ($jsonText -match '"Organization"') { $orgSchemaType = "Organization" }

    $artSchemaType = "None"
    if ($jsonText -match '"NewsArticle"') { $artSchemaType = "NewsArticle" }
    elseif ($jsonText -match '"Article"') { $artSchemaType = "Article" }
    elseif ($jsonText -match '"BlogPosting"') { $artSchemaType = "BlogPosting" }

    # E-E-A-T Properties
    $hasEthics = ($jsonText -match 'ethicsPolicy')
    $hasMasthead = ($jsonText -match 'masthead')
    $hasPostal = ($jsonText -match 'PostalAddress' -or $jsonText -match 'addressLocality' -or $jsonText -match 'addressCountry')
    $hasAuthorSameAs = ($jsonText -match '"author":\s*\{[\s\S]*?"sameAs":\s*\[?[^\]}]*(twitter|x\.com|linkedin|facebook|bsky|threads|instagram|github)')
    $hasEditor = ($jsonText -match '"editor":\s*\{')
    $editorName = if ($jsonText -match '"editor":\s*\{[\s\S]*?"name":\s*"([^"]+)"') { $matches[1] } else { "" }

    # Sémantické entity mentions
    $hasMentions = ($jsonText -match '"mentions":\s*\[')
    $mentionsCount = ([regex]::Matches($jsonText, '"@type":\s*"Thing"')).Count

    # Rich Snippets: Pros & Cons, Speakable, Rating
    $hasProsCons = ($jsonText -match 'positiveNotes' -or $jsonText -match 'negativeNotes' -or $combinedHtml -match 'entry-pros|pros-cons-wrap|review-pros')
    $hasRating = ($jsonText -match 'reviewRating' -or $jsonText -match 'ratingValue')
    $hasSpeakable = ($jsonText -match 'speakable')

    # Timezone in Schema & OpenGraph
    $datePubTz = "none"
    if ($jsonText -match '"datePublished":\s*"([^"]+)"') {
        $rawPub = $matches[1]
        if ($rawPub -match '([+-]\d{2}:\d{2})$') { $datePubTz = $matches[1] }
        elseif ($rawPub -match 'Z$') { $datePubTz = "Z" }
        else { $datePubTz = "Naive" }
    }

    $ogPubTz = "none"
    if ($artHtmlCombined -match '<meta property="article:published_time" content="([^"]+)"') {
        $rawOg = $matches[1]
        if ($rawOg -match '([+-]\d{2}:\d{2})$') { $ogPubTz = $matches[1] }
        elseif ($rawOg -match 'Z$') { $ogPubTz = "Z" }
    }

    # OpenGraph & Twitter
    $ogType = if ($artHtmlCombined -match '<meta property="og:type" content="([^"]+)"') { $matches[1] } else { "none" }
    $ogImage = if ($artHtmlCombined -match '<meta property="og:image" content="([^"]+)"') { $matches[1] } else { "" }
    $imageFormat = "JPG"
    if ($ogImage -match '\.webp(\?.*)?$') { $imageFormat = "WebP" }
    elseif ($ogImage -match '\.avif(\?.*)?$') { $imageFormat = "AVIF" }
    elseif ($ogImage -match '\.png(\?.*)?$') { $imageFormat = "PNG" }

    $twitterCard = if ($artHtmlCombined -match '<meta name="twitter:card" content="([^"]+)"') { $matches[1] } else { "none" }

    # Robots & Discover
    $maxImagePreview = if ($artHtmlCombined -match 'max-image-preview:([^"''>,\s]+)') { $matches[1] } else { "none" }
    $hasDiscoverLarge = ($maxImagePreview -eq "large" -or $artHtmlCombined -match 'max-image-preview:large')

    # Performance, LCP, Speculation & Manifest
    $hasFetchPriorityHigh = ($artHtml -match 'fetchpriority=["'']high["'']' -or $hpHtml -match 'fetchpriority=["'']high["'']')
    $hasSpeculationRules = ($artHtml -match 'type=["'']speculationrules["'']' -or $hpHtml -match 'type=["'']speculationrules["'']' -or $combinedHeaders -match 'Speculation-Rules')
    $hasManifest = ($combinedHtml -match 'rel=["'']manifest["'']' -or $combinedHtml -match 'site\.webmanifest' -or $combinedHtml -match 'manifest\.json')
    $hasWebSub = ($combinedHtml -match 'rel=["'']hub["'']' -or $combinedHtml -match 'pubsubhubbub' -or $combinedHeaders -match 'rel="hub"')

    # 4a. Resource Hints (Preconnect & DNS-Prefetch)
    $preconnectMatches = [regex]::Matches($combinedHtml, '<link\b[^>]+rel=["''](preconnect|dns-prefetch)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $preconnectCount = $preconnectMatches.Count
    $hasPreconnect = ($preconnectCount -gt 0)

    # 4b. Sitemap in robots.txt & HTTP check
    $sitemapMatches = [regex]::Matches($robotsText, '(?i)Sitemap:\s*(https?://[^\s\r\n]+)')
    $hasSitemapInRobots = ($sitemapMatches.Count -gt 0)
    $sitemapUrls = @()
    foreach ($sm in $sitemapMatches) { $sitemapUrls += $sm.Groups[1].Value.Trim() }
    if ($sitemapUrls.Count -eq 0) { $sitemapUrls += "${scheme}://${domain}/sitemap.xml" }

    $sitemapHttpCode = "000"
    foreach ($smUrl in $sitemapUrls) {
        try {
            $code = (& curl.exe -s -L -o NUL -w "%{http_code}" --connect-timeout 8 --max-time 12 -A $ua "$smUrl")
            if ($code -match '^(200|301|302)$') {
                $sitemapHttpCode = $code
                break
            }
        } catch {}
    }

    $sitemapStatus = if ($sitemapHttpCode -eq "200") {
        if ($hasSitemapInRobots) { "200 OK (v robots.txt)" } else { "200 OK (výchozí)" }
    } elseif ($sitemapHttpCode -eq "301" -or $sitemapHttpCode -eq "302") {
        "Redirect $sitemapHttpCode"
    } else {
        if ($hasSitemapInRobots) { "Chyba ($sitemapHttpCode)" } else { "Nenalezeno (404)" }
    }
    $isSitemapValid = ($sitemapHttpCode -eq "200" -or $sitemapHttpCode -eq "301")

    # 4c. Fediverse Creator Meta Tag
    $fediverseCreator = "none"
    if ($artHtml -match '<meta\b[^>]+name=["'']fediverse:creator["''][^>]+content=["'']([^"'']+)["'']' -or $artHtml -match '<meta\b[^>]+content=["'']([^"'']+)["''][^>]+name=["'']fediverse:creator["'']') {
        $fediverseCreator = $matches[1]
    } elseif ($hpHtml -match '<meta\b[^>]+name=["'']fediverse:creator["''][^>]+content=["'']([^"'']+)["'']' -or $hpHtml -match '<meta\b[^>]+content=["'']([^"'']+)["''][^>]+name=["'']fediverse:creator["'']') {
        $fediverseCreator = $matches[1]
    }
    $hasFediverse = ($fediverseCreator -ne "none")

    # 4d. Feed Content-Type & Hub inside XML
    $feedContentType = "none"
    $feedHasHub = $false
    if ($t.Rss) {
        try {
            $feedHeadersRaw = & curl.exe -s -I -L --connect-timeout 8 --max-time 12 -A $ua -H "Accept: application/rss+xml, application/atom+xml, application/xml, text/xml, */*" "$($t.Rss)"
            $feedHeaderText = ($feedHeadersRaw -join "`n")
            if ($feedHeaderText -match '(?i)content-type:\s*([^\r\n;]+)') {
                $feedContentType = $matches[1].Trim()
            }
            # Fetch feed body to verify WebSub Hub and real XML content
            $feedBodyRaw = & curl.exe -s -L --connect-timeout 8 --max-time 12 -A $ua -H "Accept: application/rss+xml, application/atom+xml, application/xml, text/xml, */*" "$($t.Rss)"
            $feedBodyText = ($feedBodyRaw -join "`n")
            if ($feedBodyText -match 'rel=["'']hub["'']' -or $feedBodyText -match '<(atom:)?link[^>]+rel=["'']hub["'']' -or $feedHeaderText -match 'rel="hub"') {
                $feedHasHub = $true
            }
            if ($feedContentType -notmatch 'xml' -and ($feedBodyText -match '^\s*<\?xml' -or $feedBodyText -match '^\s*<rss' -or $feedBodyText -match '^\s*<feed')) {
                $feedContentType = "application/rss+xml"
            }
        } catch {}
    }
    $isFeedXml = ($feedContentType -match 'xml')

    # 4e. PWA Manifest MIME check
    $manifestMime = "none"
    $hasManifestMime = $false
    $manifestUrlMatch = [regex]::Match($combinedHtml, '<link\b[^>]+rel=["'']manifest["''][^>]+href=["'']([^"'']+)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($manifestUrlMatch.Success) {
        $mUrl = $manifestUrlMatch.Groups[1].Value
        if ($mUrl -notmatch '^https?://') {
            $mUrl = "${scheme}://${domain}/" + $mUrl.TrimStart('/')
        }
        try {
            $mHeadersRaw = & curl.exe -s -I -L --connect-timeout 6 --max-time 10 -A $ua "$mUrl"
            $mHeaders = ($mHeadersRaw -join "`n")
            if ($mHeaders -match '(?i)content-type:\s*([^\r\n;]+)') {
                $manifestMime = $matches[1].Trim()
                if ($manifestMime -match 'manifest\+json|application/json') {
                    $hasManifestMime = $true
                }
            }
        } catch {}
    }

    # 4f. HTML5 Clean (No deprecated type="text/css" or type="text/javascript")
    $legacyCssCount = ([regex]::Matches($artHtml, '<style[^>]+type=["'']text/css["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $legacyJsCount = ([regex]::Matches($artHtml, '<script[^>]+type=["'']text/javascript["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $html5Clean = ($legacyCssCount -eq 0 -and $legacyJsCount -eq 0)

    # 4g. Video & Podcast Schema
    $hasVideoSchema = ($jsonText -match '"VideoObject"')
    $hasPodcastSchema = ($jsonText -match '"PodcastEpisode"' -or $jsonText -match '"PodcastSeries"')
    $mediaSchema = "none"
    if ($hasVideoSchema -and $hasPodcastSchema) { $mediaSchema = "Video + Podcast" }
    elseif ($hasVideoSchema) { $mediaSchema = "VideoObject" }
    elseif ($hasPodcastSchema) { $mediaSchema = "PodcastEpisode" }

    # 4h. Official W3C Nu HTML Validator API Check
    $w3cErrors = 0
    $w3cWarnings = 0
    $w3cChecked = $false
    if ($artUrl) {
        try {
            $cleanArtUrl = $artUrl -replace '\?nocache=\d+', ''
            $encodedArtUrl = [System.Uri]::EscapeDataString($cleanArtUrl)
            $w3cRaw = & curl.exe -s --connect-timeout 8 --max-time 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) W3C_Validator_Audit/1.0" "https://validator.w3.org/nu/?doc=$encodedArtUrl&out=json"
            $w3cText = ($w3cRaw -join "`n")
            if ($w3cText -match '"messages"') {
                $w3cJson = $w3cText | ConvertFrom-Json
                $w3cErrors = @($w3cJson.messages | Where-Object { $_.type -eq 'error' }).Count
                $w3cWarnings = @($w3cJson.messages | Where-Object { $_.type -eq 'info' -and $_.subType -eq 'warning' }).Count
                $w3cChecked = $true
            }
        } catch {}
    }
    $w3cStatus = if ($w3cChecked) {
        if ($w3cErrors -eq 0 -and $w3cWarnings -eq 0) { "0 chyb (100% Validní)" }
        elseif ($w3cErrors -eq 0) { "0 chyb ($w3cWarnings varování)" }
        else { "$w3cErrors chyb, $w3cWarnings varování" }
    } else { "Neověřeno" }
    $isW3cClean = ($w3cChecked -and $w3cErrors -eq 0)

    # AI Bots in robots.txt
    $blocksAi = ($robotsText -match 'User-agent:\s*(GPTBot|Google-Extended|ClaudeBot|PerplexityBot|CCBot)[\s\S]*?Disallow:\s*/')

    # Consent Mode v2 & CMP Platform Detection
    $cmpSystem = "Basic_Bar"
    $hasConsentV2 = $false

    if ($combinedHtml -match 'complianz-gdpr-premium|cmplz-tcf|tcf_active') {
        $cmpSystem = "Complianz_TCF_CoMoV2"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match 'cmplz|complianz') {
        $cmpSystem = "Complianz_CoMoV2"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match 'didomi|privacy\.cpex\.cz|cpex-cmp') {
        $cmpSystem = "Didomi_CPEX_TCF"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match 'cookiebot|consent\.cookiebot\.com') {
        $cmpSystem = "Cookiebot_TCF"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match 'fundingchoices|fundingchoicesmessages') {
        $cmpSystem = "Google_FundingChoices"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match 'ad_user_data' -or ($combinedHtml -match 'gtag\s*\(\s*["'']consent["'']' -and $combinedHtml -match 'ad_personalization')) {
        $cmpSystem = "Google_ConsentModeV2"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match '"consent-method":"iab_tcf"') {
        $cmpSystem = "AdvancedAds_TCF"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match '24net\.cz/resources/js/cmp\.js') {
        $cmpSystem = "24net_IAB_CMP"
        $hasConsentV2 = $true
    } elseif ($combinedHtml -match 'cmp\.js') {
        $cmpSystem = "Custom_CMP"
        $hasConsentV2 = $false
    } elseif ($combinedHtml -match 'gtag\s*\(\s*["'']consent["'']') {
        $cmpSystem = "Consent_v1"
        $hasConsentV2 = $false
    }

    # Comments System
    $commentsSystem = "Custom"
    if ($artHtml -match 'disqus\.com') { $commentsSystem = "Disqus" }
    elseif ($artHtml -match 'facebook\.com/plugins/comments') { $commentsSystem = "Facebook" }
    elseif ($t.Name -eq "MobilMania.cz" -or $t.Name -eq "Živě.cz") { $commentsSystem = "SuperForum" }
    elseif ($t.Name -eq "Chip.cz" -or $t.Name -eq "ITMix.cz" -or $t.Name -eq "Wired.cz" -or $t.Name -eq "CzechCrunch (CC.cz)") { $commentsSystem = "Disabled" }
    elseif ($combinedHtml -match 'wp-comments|comment-respond') { $commentsSystem = "WordPress" }

    # DOM & H1
    $h1Count = ([regex]::Matches($artHtml, '<h1\b[^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
    $domTags = ([regex]::Matches($artHtml, '<[a-zA-Z0-9]+(\s|>)')).Count

    # SwG / Reader Revenue
    $hasSwG = ($artHtml -match 'news\.google\.com/swg' -or $artHtml -match 'subscriptions\.google' -or $hpHtml -match 'swg-basic\.js')

    # Mobile specific checks
    $hasViewport = ($artHtmlM -match '<meta\b[^>]+name=["'']viewport["''][^>]*>')
    $hasViewportWidthDevice = ($artHtmlM -match '<meta\b[^>]+content=["''][^"'']*width=device-width[^"'']*["''][^>]*>')
    $isViewportZoomable = -not ($artHtmlM -match 'user-scalable\s*=\s*(no|0)|maximum-scale\s*=\s*1(\.0)?')
    $isViewportValid = ($hasViewport -and $hasViewportWidthDevice)

    $hasThemeColor = ($artHtmlM -match '<meta\b[^>]+name=["'']theme-color["'']')
    $hasAppleTouchIcon = ($artHtmlM -match '<link\b[^>]+rel=["''][^"'']*apple-touch-icon[^"'']*["'']')
    $hasManifestM = ($artHtmlM -match '<link\b[^>]+rel=["'']manifest["'']')
    $hasFetchPriorityM = ($artHtmlM -match 'fetchpriority=["'']high["'']')
    $hasResponsiveImagesM = ($artHtmlM -match '<picture|srcset=')
    $h1CountM = ([regex]::Matches($artHtmlM, '<h1\b[^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count

    # === EXACT FAIR SCORING (Dual Mobile & Desktop 100 Max) ===
    # === STRICT CALIBRATED DUAL SCORING (Max 100) ===
    # A. Společný redakční, E-E-A-T & Discover základ (Max 48 b)
    $baseScore = 0
    $baseReasons = @()

    # Organizace & Sídlo (18 b)
    if ($orgSchemaType -eq "NewsMediaOrganization") { $baseScore += 8; $baseReasons += "+8b: NewsMediaOrganization" }
    elseif ($orgSchemaType -eq "Organization") { $baseScore += 4; $baseReasons += "+4b: Organization" }
    
    if ($hasEthics -and $hasMasthead) { $baseScore += 5; $baseReasons += "+5b: Kodex i Tiráž" }
    elseif ($hasEthics -or $hasMasthead) { $baseScore += 2; $baseReasons += "+2b: Část E-E-A-T" }

    if ($hasPostal) { $baseScore += 3; $baseReasons += "+3b: Poštovní adresa sídla" }
    if ($issnNumber -ne "none") { $baseScore += 2; $baseReasons += "+2b: ISSN registrace ($issnNumber)" }

    # Článek & Autorita (26 b)
    if ($artSchemaType -eq "NewsArticle") { $baseScore += 10; $baseReasons += "+10b: NewsArticle schéma" }
    elseif ($artSchemaType -eq "Article") { $baseScore += 5; $baseReasons += "+5b: Article schéma" }
    elseif ($artSchemaType -eq "BlogPosting") { $baseScore += 3; $baseReasons += "+3b: BlogPosting schéma" }

    if ($datePubTz -eq "+02:00" -or $datePubTz -eq "+01:00") { $baseScore += 6; $baseReasons += "+6b: Platná lokální zóna ($datePubTz)" }
    elseif ($datePubTz -match "Z|\+00:00") { $baseScore += 2; $baseReasons += "+2b: UTC čas (zpoždění v Discover)" }

    if ($hasAuthorSameAs) { $baseScore += 4; $baseReasons += "+4b: Sociální sítě autora" }
    if ($hasEditor) { $baseScore += 4; $baseReasons += "+4b: Redakční garant (editor: $editorName)" }
    if ($memberships.Count -gt 0) { $baseScore += 2; $baseReasons += "+2b: Oborové členství ($orgText)" }

    # Sociální sítě & Discover (4 b)
    if ($ogType -eq "article") { $baseScore += 2; $baseReasons += "+2b: og:type=article" }
    if ($hasDiscoverLarge) { $baseScore += 2; $baseReasons += "+2b: max-image-preview:large" }

    # B. Desktop specifické body (Max 52 b add-on -> 100 Max)
    $desktopScore = $baseScore
    $desktopReasons = @($baseReasons)

    if ($hasHttp3) { $desktopScore += 4; $desktopReasons += "+4b: HTTP/3 QUIC" }
    if ($hasHsts) { $desktopScore += 5; $desktopReasons += "+5b: HSTS aktivní" }
    if ($hasNosniff) { $desktopScore += 4; $desktopReasons += "+4b: X-Content-Type-Options nosniff" }
    if ($hasXfo) { $desktopScore += 4; $desktopReasons += "+4b: X-Frame-Options ochrana" }
    if ($isW3cClean) { $desktopScore += 5; $desktopReasons += "+5b: W3C Validní HTML5 ($w3cStatus)" }
    if ($hasWebSub) { $desktopScore += 5; $desktopReasons += "+5b: W3C WebSub Huby" }
    if ($isFeedXml) { $desktopScore += 2; $desktopReasons += "+2b: Validní XML Feed ($feedContentType)" }
    if ($isSitemapValid) { $desktopScore += 2; $desktopReasons += "+2b: Sitemap XML ($sitemapStatus)" }
    if ($hasPreconnect) { $desktopScore += 3; $desktopReasons += "+3b: Preconnect & Hints ($preconnectCount)" }
    if ($hasSpeculationRules) { $desktopScore += 3; $desktopReasons += "+3b: Speculation Rules" }
    if ($hasSpeakable) { $desktopScore += 3; $desktopReasons += "+3b: Google Assistant speakable" }

    # Přísná rychlost na Desktopu
    if ($artLcpMsD -gt 0 -and $artLcpMsD -lt 250) { $desktopScore += 6; $desktopReasons += "+6b: Desktop LCP bleskové ($artLcpMsD ms)" }
    elseif ($artLcpMsD -gt 0 -and $artLcpMsD -lt 800) { $desktopScore += 3; $desktopReasons += "+3b: Desktop LCP dobré ($artLcpMsD ms)" }
    elseif ($artLcpMsD -gt 0 -and $artLcpMsD -lt 1500) { $desktopScore += 1; $desktopReasons += "+1b: Desktop LCP ($artLcpMsD ms)" }

    if ($artTtfbMsD -gt 0 -and $artTtfbMsD -lt 60) { $desktopScore += 6; $desktopReasons += "+6b: Desktop TTFB bleskové ($artTtfbMsD ms)" }
    elseif ($artTtfbMsD -gt 0 -and $artTtfbMsD -lt 150) { $desktopScore += 3; $desktopReasons += "+3b: Desktop TTFB dobré ($artTtfbMsD ms)" }

    if ($desktopScore -gt 100) { $desktopScore = 100 }

    # C. Mobilní specifické body (Max 52 b add-on -> 100 Max)
    $mobileScore = $baseScore
    $mobileReasons = @($baseReasons)

    if ($isViewportValid) { $mobileScore += 2; $mobileReasons += "+2b: Validní mobilní Viewport" }
    if ($isViewportZoomable) { $mobileScore += 2; $mobileReasons += "+2b: Přístupný Viewport" }
    if ($hasHsts) { $mobileScore += 4; $mobileReasons += "+4b: HSTS šifrování pro mobil" }
    if ($hasManifestM -or $hasManifest) { $mobileScore += 4; $mobileReasons += "+4b: Web Manifest & PWA Ready" }
    if ($hasAppleTouchIcon -or $hasThemeColor) { $mobileScore += 2; $mobileReasons += "+2b: Touch Icon & Theme-Color" }
    if ($hasFetchPriorityM -or $hasFetchPriorityHigh) { $mobileScore += 3; $mobileReasons += "+3b: fetchpriority=high na mobilní fotce" }
    if ($hasResponsiveImagesM) { $mobileScore += 2; $mobileReasons += "+2b: Responzivní obrázky (srcset)" }
    if ($hasWebSub) { $mobileScore += 4; $mobileReasons += "+4b: Realtime WebSub Push na mobil" }
    if ($hasFediverse) { $mobileScore += 3; $mobileReasons += "+3b: Fediverse Creator ($fediverseCreator)" }
    if ($hasMentions) { $mobileScore += 5; $mobileReasons += "+5b: Sémantické entity (mentions: Thing)" }
    if ($hasSpeakable) { $mobileScore += 3; $mobileReasons += "+3b: Google Assistant speakable" }
    if ($h1CountM -eq 1 -or $h1Count -eq 1) { $mobileScore += 2; $mobileReasons += "+2b: Čistá H1 hierarchie (1x H1)" }

    # Přísná rychlost na Mobilu
    if ($artLcpMsM -gt 0 -and $artLcpMsM -lt 150) { $mobileScore += 8; $mobileReasons += "+8b: Mobilní LCP bleskové ($artLcpMsM ms)" }
    elseif ($artLcpMsM -gt 0 -and $artLcpMsM -lt 400) { $mobileScore += 4; $mobileReasons += "+4b: Mobilní LCP dobré ($artLcpMsM ms)" }
    elseif ($artLcpMsM -gt 0 -and $artLcpMsM -lt 1000) { $mobileScore += 2; $mobileReasons += "+2b: Mobilní LCP ($artLcpMsM ms)" }

    if ($artTtfbMsM -gt 0 -and $artTtfbMsM -lt 60) { $mobileScore += 5; $mobileReasons += "+5b: Mobilní TTFB bleskové ($artTtfbMsM ms)" }
    elseif ($artTtfbMsM -gt 0 -and $artTtfbMsM -lt 150) { $mobileScore += 2; $mobileReasons += "+2b: Mobilní TTFB dobré ($artTtfbMsM ms)" }

    if ($artPayloadM -gt 0 -and $artPayloadM -lt 60) { $mobileScore += 3; $mobileReasons += "+3b: Datově úsporný mobil ($artPayloadM kB)" }
    elseif ($artPayloadM -gt 0 -and $artPayloadM -lt 120) { $mobileScore += 1; $mobileReasons += "+1b: Datová zátěž ($artPayloadM kB)" }

    if ($mobileScore -gt 100) { $mobileScore = 100 }

    # D. Celkové kombinované skóre
    $overallScore = [int][Math]::Round(($desktopScore + $mobileScore) / 2)

    $item = [PSCustomObject]@{
        Name               = $t.Name
        HpUrl              = $t.Hp
        ArticleUrl         = $artUrl -replace '\?nocache=\d+', ''
        TotalScore         = $overallScore
        OverallScore       = $overallScore
        DesktopScore       = $desktopScore
        MobileScore        = $mobileScore
        ScoreReasons       = ($desktopReasons -join ", ")
        DesktopReasons     = ($desktopReasons -join ", ")
        MobileReasons      = ($mobileReasons -join ", ")
        HpTtfbMs           = $hpTtfbMsD
        ArtTtfbMs          = $artTtfbMsD
        ArtLcpMs           = $artLcpMsD
        ArtFcpMs           = $artFcpMsD
        DesktopTtfbMs      = $artTtfbMsD
        DesktopLcpMs       = $artLcpMsD
        DesktopPayloadKb   = $artPayloadD
        MobileTtfbMs       = $artTtfbMsM
        MobileLcpMs        = $artLcpMsM
        MobilePayloadKb    = $artPayloadM
        ViewportValid      = $isViewportValid
        ViewportZoomable   = $isViewportZoomable
        PwaManifest        = ($hasManifestM -or $hasManifest)
        AppleTouchIcon     = $hasAppleTouchIcon
        ThemeColor         = $hasThemeColor
        FetchPriorityHighM = $hasFetchPriorityM
        ResponsiveImagesM  = $hasResponsiveImagesM
        ISSN               = $issnNumber
        Memberships        = $orgText
        HSTS               = $hasHsts
        Nosniff            = $hasNosniff
        XFO                = $hasXfo
        HTTP3              = $hasHttp3
        OrgSchema          = $orgSchemaType
        ArtSchema          = $artSchemaType
        Ethics             = $hasEthics
        Masthead           = $hasMasthead
        PostalAddress      = $hasPostal
        AuthorSameAs       = $hasAuthorSameAs
        Editor             = $hasEditor
        EditorName         = $editorName
        Mentions           = $hasMentions
        MentionsCount      = $mentionsCount
        Speakable          = $hasSpeakable
        Timezone           = $datePubTz
        OgType             = $ogType
        OgImageFormat      = $imageFormat
        DiscoverLarge      = $hasDiscoverLarge
        FetchPriority      = $hasFetchPriorityHigh
        Preconnect         = $hasPreconnect
        PreconnectCount    = $preconnectCount
        Speculation        = $hasSpeculationRules
        Manifest           = $hasManifest
        ManifestMime       = $manifestMime
        WebSub             = $hasWebSub
        FeedContentType    = $feedContentType
        FeedHasHub         = $feedHasHub
        SitemapStatus      = $sitemapStatus
        IsSitemapValid     = $isSitemapValid
        Fediverse          = $hasFediverse
        FediverseUser      = $fediverseCreator
        Html5Clean         = $html5Clean
        LegacyCssCount     = $legacyCssCount
        LegacyJsCount      = $legacyJsCount
        W3CErrors          = $w3cErrors
        W3CWarnings        = $w3cWarnings
        W3CStatus          = $w3cStatus
        IsW3cClean         = $isW3cClean
        MediaSchema        = $mediaSchema
        BlocksAi           = $blocksAi
        ConsentV2          = $hasConsentV2
        CMP                = $cmpSystem
        Comments           = $commentsSystem
        H1Count            = $h1Count
        DomTags            = $domTags
        SwG                = $hasSwG
    }

    $auditItems += $item
}

# Sort by TotalScore Descending
$sorted = $auditItems | Sort-Object -Property TotalScore -Descending

# Save raw & scored JSON
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$jsonRaw = $sorted | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText("$dataDir\raw-audit-$today.json", $jsonRaw, $utf8NoBom)
[System.IO.File]::WriteAllText("$dataDir\scored-$today.json", ($sorted | Select-Object Name, TotalScore, OverallScore, DesktopScore, MobileScore, DesktopReasons, MobileReasons | ConvertTo-Json -Depth 3), $utf8NoBom)

Write-Host "Data saved. Generating Master HTML Matrix..."

$jsonEmbedded = $sorted | ConvertTo-Json -Depth 5

$templateFile = "$benchmarkRoot\template.html"
if (Test-Path $templateFile) {
    $templateHtml = [System.IO.File]::ReadAllText($templateFile, [System.Text.Encoding]::UTF8)
    $finalHtml = $templateHtml.Replace('__DATE__', $today).Replace('__COUNT__', "$($targets.Count)").Replace('__JSON_DATA__', $jsonEmbedded)
    [System.IO.File]::WriteAllText($htmlFile, $finalHtml, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText("$benchmarkRoot\index.html", $finalHtml, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText("$PSScriptRoot\..\..\index.html", $finalHtml, [System.Text.Encoding]::UTF8)
    
    $docsDir = "$PSScriptRoot\..\..\docs"
    if (!(Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
    [System.IO.File]::WriteAllText("$docsDir\index.html", $finalHtml, [System.Text.Encoding]::UTF8)

    Write-Host "Master Benchmark HTML Matrix successfully created: $htmlFile, index.html & docs/index.html"

    # Optional sync to public-benchmark (only when explicitly requested via -PushPublic)
    if ($PushPublic) {
        $pubDir = "$PSScriptRoot\..\..\public-benchmark"
        if (!(Test-Path "$pubDir\.git")) {
            $pubDir = "C:\Users\premy\.gemini\antigravity-ide\brain\72564e42-88cb-4920-a972-1524155e7956\scratch\czech-tech-benchmark"
        }
        if (Test-Path "$pubDir\.git") {
            Write-Host "Syncing to public-benchmark repository..."
            Copy-Item -Path "$dataDir\raw-audit-$today.json" -Destination "$pubDir\data\" -Force
            Copy-Item -Path "$dataDir\scored-$today.json" -Destination "$pubDir\data\" -Force
            Copy-Item -Path $htmlFile -Destination "$pubDir\$today.html" -Force
            Copy-Item -Path $htmlFile -Destination "$pubDir\index.html" -Force
            Copy-Item -Path "$benchmarkRoot\README.md" -Destination "$pubDir\README.md" -Force
            Copy-Item -Path "$benchmarkRoot\targets.txt" -Destination "$pubDir\targets.txt" -Force
            Copy-Item -Path "$benchmarkRoot\template.html" -Destination "$pubDir\template.html" -Force
            Copy-Item -Path "$benchmarkRoot\scripts\run-audit.ps1" -Destination "$pubDir\scripts\run-audit.ps1" -Force
            
            git -C $pubDir add -A
            git -C $pubDir commit -m "Update benchmark data for $today (20 portals)"
            git -C $pubDir push origin main
            Write-Host "Public benchmark repository updated and pushed."
        }
    }
} else {
    Write-Host "Error: Template file $templateFile not found!"
}

# Cleanup Chrome process
if ($chromeProc -and -not $chromeProc.HasExited) {
    Stop-Process -Id $chromeProc.Id -Force -ErrorAction SilentlyContinue
}
if (Test-Path $chromeTempDir) {
    Remove-Item -Path $chromeTempDir -Recurse -Force -ErrorAction SilentlyContinue
}
