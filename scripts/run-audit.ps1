param(
    [switch]$PushPublic = $false
)

# Master Technical SEO & Architecture Benchmark for 16 Czech Tech Portals
$ErrorActionPreference = "Continue"
$OutputEncoding = [System.Text.Encoding]::UTF8
$ConsoleOutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$today = (Get-Date).ToString("yyyy-MM-dd")
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"

$benchmarkRoot = "c:\02 vyvoj\Dotekomanie31\benchmark"
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

Write-Host "Starting Master Technical Audit for $today across $($targets.Count) portals..."
$auditItems = @()

foreach ($t in $targets) {
    Write-Host "Auditing: $($t.Name)..."
    $nocache = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $hpUrl = "$($t.Hp)?nocache=$nocache"
    $artUrl = if ($t.ArtOverride) { "$($t.ArtOverride)?nocache=$nocache" } else { "" }

    # 1. Fetch HP & Headers
    $hpHeadersRaw = & curl.exe -s -I --connect-timeout 8 --max-time 15 -A $ua $hpUrl
    $hpHeaders = ($hpHeadersRaw -join "`n")
    $hpHtmlRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $ua $hpUrl
    $hpHtml = ($hpHtmlRaw -join "`n")

    # 2. Dynamic Multi-Article Resolution - výběr vzorku 3 až 4 čerstvých článků z RSS nebo HP
    $articleUrls = @()
    if ($t.Rss) {
        try {
            $rssRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $ua "$($t.Rss)"
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

    # 3. Fetch All Resolved Articles
    $artHtmlList = @()
    $artHeadersList = @()
    $artUrl = if ($articleUrls.Count -gt 0) { $articleUrls[0] } else { "" }

    foreach ($aUrl in $articleUrls) {
        try {
            $aHeadRaw = & curl.exe -s -I --connect-timeout 6 --max-time 10 -A $ua "$aUrl"
            $aHtmlRaw = & curl.exe -Ls --connect-timeout 6 --max-time 10 -A $ua "$aUrl"
            $artHeadersList += ($aHeadRaw -join "`n")
            $artHtmlList += ($aHtmlRaw -join "`n")
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
    $hasSitemapInRobots = ($robotsText -match '(?i)Sitemap:\s*(https?://[^\s\r\n]+)')
    $sitemapUrl = if ($hasSitemapInRobots) { $matches[1].Trim() } else { "${scheme}://${domain}/sitemap.xml" }
    $sitemapHttpCode = "000"
    try {
        $smHeaderRaw = & curl.exe -s -I -L --connect-timeout 6 --max-time 10 -A $ua "$sitemapUrl"
        $smHeader = ($smHeaderRaw -join "`n")
        $codeMatches = [regex]::Matches($smHeader, 'HTTP/\S+\s+(\d{3})')
        if ($codeMatches.Count -gt 0) {
            $sitemapHttpCode = $codeMatches[$codeMatches.Count - 1].Groups[1].Value
        }
    } catch {}
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
            $feedHeadersRaw = & curl.exe -s -I --connect-timeout 6 --max-time 10 -A $ua "$($t.Rss)"
            $feedHeaderText = ($feedHeadersRaw -join "`n")
            if ($feedHeaderText -match '(?i)content-type:\s*([^\r\n;]+)') {
                $feedContentType = $matches[1].Trim()
            }
            if ($rssText -match 'rel=["'']hub["'']' -or $rssText -match '<(atom:)?link[^>]+rel=["'']hub["'']') {
                $feedHasHub = $true
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
                $w3cErrors = ($w3cJson.messages | Where-Object { $_.type -eq 'error' }).Count
                $w3cWarnings = ($w3cJson.messages | Where-Object { $_.type -eq 'info' -and $_.subType -eq 'warning' }).Count
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

    if ($combinedHtml -match 'cmplz|complianz') {
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

    # === EXACT FAIR SCORING (100 Max) ===
    $score = 0
    $reasons = @()

    # 1. Organizace & ISSN (20 b)
    if ($orgSchemaType -eq "NewsMediaOrganization") { $score += 8; $reasons += "+8b: NewsMediaOrganization" }
    elseif ($orgSchemaType -eq "Organization") { $score += 4; $reasons += "+4b: Organization" }
    
    if ($hasEthics -and $hasMasthead) { $score += 5; $reasons += "+5b: Kodex i Tiráž" }
    elseif ($hasEthics -or $hasMasthead) { $score += 2; $reasons += "+2b: Část E-E-A-T" }

    if ($hasPostal) { $score += 3; $reasons += "+3b: Poštovní adresa sídla" }
    if ($issnNumber -ne "none") { $score += 2; $reasons += "+2b: ISSN registrace ($issnNumber)" }
    if ($memberships.Count -gt 0) { $score += 2; $reasons += "+2b: Oborové členství ($orgText)" }

    # 2. Článek & E-E-A-T (30 b)
    if ($artSchemaType -eq "NewsArticle") { $score += 10; $reasons += "+10b: NewsArticle schéma" }
    elseif ($artSchemaType -eq "Article") { $score += 5; $reasons += "+5b: Article schéma" }
    elseif ($artSchemaType -eq "BlogPosting") { $score += 3; $reasons += "+3b: BlogPosting schéma" }

    if ($datePubTz -eq "+02:00" -or $datePubTz -eq "+01:00") { $score += 6; $reasons += "+6b: Platná lokální zóna ($datePubTz)" }
    elseif ($datePubTz -match "Z|\+00:00") { $score += 3; $reasons += "+3b: UTC čas (zpoždění v Discover)" }

    if ($hasAuthorSameAs) { $score += 4; $reasons += "+4b: Sociální sítě autora" }
    if ($hasEditor) { $score += 4; $reasons += "+4b: Redakční garant (editor: $editorName)" }
    if ($hasMentions) { $score += 4; $reasons += "+4b: Sémantické entity (mentions: Thing)" }
    if ($hasSpeakable) { $score += 2; $reasons += "+2b: Google Assistant speakable" }

    # 3. OpenGraph & Discover (15 b)
    if ($ogType -eq "article") { $score += 4; $reasons += "+4b: og:type=article" }
    if ($ogPubTz -eq "+02:00" -or $ogPubTz -eq "+01:00") { $score += 4; $reasons += "+4b: OG publikováno v lokálním čase" }
    elseif ($ogPubTz -match "Z|\+00:00") { $score += 2; $reasons += "+2b: OG publikováno v UTC" }
    if ($twitterCard -eq "summary_large_image") { $score += 4; $reasons += "+4b: Twitter Large Card" }
    if ($hasDiscoverLarge) { $score += 3; $reasons += "+3b: max-image-preview:large" }

    # 4. Rychlost, WebSub & Moderní Web (20 b)
    if ($hasWebSub) { $score += 5; $reasons += "+5b: W3C WebSub Realtime Push Huby" }
    if ($isFeedXml) { $score += 2; $reasons += "+2b: Validní XML Feed ($feedContentType)" }
    if ($hasHttp3) { $score += 3; $reasons += "+3b: HTTP/3 QUIC podpora" }
    if ($hasManifest) { $score += 2; $reasons += "+2b: Web Manifest & PWA" }
    if ($hasPreconnect) { $score += 2; $reasons += "+2b: Preconnect & DNS Hints ($preconnectCount)" }
    if ($hasFetchPriorityHigh) { $score += 2; $reasons += "+2b: fetchpriority=high u LCP fotky" }
    if ($hasSpeculationRules) { $score += 2; $reasons += "+2b: Speculation Rules instant prerender" }
    if ($hasFediverse) { $score += 2; $reasons += "+2b: Fediverse Creator ($fediverseCreator)" }

    # 5. Bezpečnost & Standardy (15 b)
    if ($hasHsts) { $score += 4; $reasons += "+4b: HSTS aktivní" }
    if ($hasNosniff) { $score += 3; $reasons += "+3b: X-Content-Type-Options nosniff" }
    if ($hasXfo) { $score += 3; $reasons += "+3b: X-Frame-Options ochrana" }
    if ($isSitemapValid) { $score += 2; $reasons += "+2b: Sitemap XML ($sitemapStatus)" }
    if ($isW3cClean) { $score += 3; $reasons += "+3b: W3C Validní HTML5 ($w3cStatus)" }
    elseif ($h1Count -eq 1) { $score += 2; $reasons += "+2b: Čistá H1 hierarchie (1x H1)" }

    if ($score -gt 100) { $score = 100 }

    $item = [PSCustomObject]@{
        Name           = $t.Name
        HpUrl          = $t.Hp
        ArticleUrl     = $artUrl -replace '\?nocache=\d+', ''
        ISSN           = $issnNumber
        Memberships    = $orgText
        HSTS           = $hasHsts
        Nosniff        = $hasNosniff
        XFO            = $hasXfo
        HTTP3          = $hasHttp3
        OrgSchema      = $orgSchemaType
        ArtSchema      = $artSchemaType
        Ethics         = $hasEthics
        Masthead       = $hasMasthead
        PostalAddress  = $hasPostal
        AuthorSameAs   = $hasAuthorSameAs
        Editor         = $hasEditor
        EditorName     = $editorName
        Mentions       = $hasMentions
        MentionsCount  = $mentionsCount
        Speakable      = $hasSpeakable
        Timezone       = $datePubTz
        OgType         = $ogType
        OgImageFormat  = $imageFormat
        DiscoverLarge  = $hasDiscoverLarge
        FetchPriority  = $hasFetchPriorityHigh
        Preconnect     = $hasPreconnect
        PreconnectCount= $preconnectCount
        Speculation    = $hasSpeculationRules
        Manifest       = $hasManifest
        ManifestMime   = $manifestMime
        WebSub         = $hasWebSub
        FeedContentType= $feedContentType
        FeedHasHub     = $feedHasHub
        SitemapStatus  = $sitemapStatus
        IsSitemapValid = $isSitemapValid
        Fediverse      = $hasFediverse
        FediverseUser  = $fediverseCreator
        Html5Clean     = $html5Clean
        LegacyCssCount = $legacyCssCount
        LegacyJsCount  = $legacyJsCount
        W3CErrors      = $w3cErrors
        W3CWarnings    = $w3cWarnings
        W3CStatus      = $w3cStatus
        IsW3cClean     = $isW3cClean
        MediaSchema    = $mediaSchema
        BlocksAi       = $blocksAi
        ConsentV2      = $hasConsentV2
        CMP            = $cmpSystem
        Comments       = $commentsSystem
        H1Count        = $h1Count
        DomTags        = $domTags
        SwG            = $hasSwG
        TotalScore     = $score
        ScoreReasons   = ($reasons -join ", ")
    }

    $auditItems += $item
}

# Sort by TotalScore Descending
$sorted = $auditItems | Sort-Object -Property TotalScore -Descending

# Save raw & scored JSON
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$jsonRaw = $sorted | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText("$dataDir\raw-audit-$today.json", $jsonRaw, $utf8NoBom)
[System.IO.File]::WriteAllText("$dataDir\scored-$today.json", ($sorted | Select-Object Name, TotalScore, ScoreReasons | ConvertTo-Json -Depth 3), $utf8NoBom)

Write-Host "Data saved. Generating Master HTML Matrix..."

$jsonEmbedded = $sorted | ConvertTo-Json -Depth 5

$templateFile = "$benchmarkRoot\template.html"
if (Test-Path $templateFile) {
    $templateHtml = [System.IO.File]::ReadAllText($templateFile, [System.Text.Encoding]::UTF8)
    $finalHtml = $templateHtml.Replace('__DATE__', $today).Replace('__JSON_DATA__', $jsonEmbedded)
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
        if (Test-Path "$pubDir\.git") {
            Write-Host "Syncing to public-benchmark repository..."
            Copy-Item -Path "$dataDir\raw-audit-$today.json" -Destination "$pubDir\data\" -Force
            Copy-Item -Path "$dataDir\scored-$today.json" -Destination "$pubDir\data\" -Force
            Copy-Item -Path $htmlFile -Destination "$pubDir\$today.html" -Force
            Copy-Item -Path $htmlFile -Destination "$pubDir\index.html" -Force
            Copy-Item -Path "$benchmarkRoot\README.md" -Destination "$pubDir\README.md" -Force
            Copy-Item -Path "$benchmarkRoot\targets.txt" -Destination "$pubDir\targets.txt" -Force
            Copy-Item -Path "$benchmarkRoot\template.html" -Destination "$pubDir\template.html" -Force
            
            git -C $pubDir add -A
            git -C $pubDir commit -m "Update benchmark data for $today" --quiet
            git -C $pubDir push origin main --quiet
            Write-Host "Public benchmark repository updated and pushed."
        }
    }
} else {
    Write-Host "Error: Template file $templateFile not found!"
}
