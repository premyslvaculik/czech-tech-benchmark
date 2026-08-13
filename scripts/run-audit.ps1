# Master Technical SEO & Architecture Benchmark for 16 Czech Tech Portals
$ErrorActionPreference = "Continue"
$OutputEncoding = [System.Text.Encoding]::UTF8
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

    # 2. Dynamic Article Resolution - vždy čerstvý nejnovější článek z RSS
    $artUrl = ""
    if ($t.Rss) {
        try {
            $rssRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $ua "$($t.Rss)?nocache=$nocache"
            $rssText = ($rssRaw -join "`n")
            $artMatch = [regex]::Match($rssText, '<item>[\s\S]*?<link>([^<]+)</link>')
            if ($artMatch.Success) {
                $artUrl = $artMatch.Groups[1].Value.Trim() + "?nocache=$nocache"
            }
        } catch {}
    }
    if (-not $artUrl -and $t.ArtOverride) {
        $artUrl = "$($t.ArtOverride)?nocache=$nocache"
    }
    if (-not $artUrl) {
        $linkMatches = [regex]::Matches($hpHtml, '<a[^>]+href=["''](https?://[^"'']+)["''][^>]*>')
        foreach ($lm in $linkMatches) {
            $u = $lm.Groups[1].Value
            if ($u -match '/(202\d|clanky|clanek|article|recenze)/' -and $u -notmatch '/(tag|kategorie|rubrika|page|autor)/') {
                $artUrl = "$u?nocache=$nocache"
                break
            }
        }
    }

    # 3. Fetch Article & Headers
    $artHeaders = ""
    $artHtml = ""
    if ($artUrl) {
        $artHeadersRaw = & curl.exe -s -I --connect-timeout 8 --max-time 15 -A $ua $artUrl
        $artHeaders = ($artHeadersRaw -join "`n")
        $artHtmlRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $ua $artUrl
        $artHtml = ($artHtmlRaw -join "`n")
    }

    # 4. Fetch Robots.txt & O-nas
    $domain = ([uri]$t.Hp).Host
    $scheme = ([uri]$t.Hp).Scheme
    $robotsUrl = "${scheme}://${domain}/robots.txt?nocache=$nocache"
    $robotsRaw = & curl.exe -Ls --connect-timeout 8 --max-time 15 -A $ua $robotsUrl
    $robotsText = ($robotsRaw -join "`n")

    $combinedHtml = $hpHtml + "`n" + $artHtml
    $combinedHeaders = $hpHeaders + "`n" + $artHeaders

    # === TECHNICAL METRICS EXTRACTION ===
    
    # 1. ISSN Detection (HTML body, footer, or Schema.org)
    $issnMatch = [regex]::Match($combinedHtml, 'ISSN\s*[:\s\-]?\s*([0-9]{4}\s*[-–—]\s*[0-9]{3}[0-9xX])', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $issnMatch.Success) {
        $issnMatch = [regex]::Match($jsonText, '"issn":\s*"([^"]+)"')
    }
    $issnNumber = if ($issnMatch.Success) { $issnMatch.Groups[1].Value.Replace('–', '-').Replace('—', '-').Trim() } else { "none" }

    # 2. Memberships
    $memberships = @()
    if ($combinedHtml -match 'SPIR|NetMonitor|Sdružení pro internetový rozvoj') { $memberships += "SPIR" }
    if ($combinedHtml -match 'Unie vydavatelů|Czech Publishers Union') { $memberships += "UnieVydavatelu" }
    if ($combinedHtml -match 'Syndikát novinářů|IFJ') { $memberships += "SyndikatNovinaru" }
    if ($combinedHtml -match 'IAB Europe|TCF') { $memberships += "IAB_TCF" }
    if ($combinedHtml -match 'Ministerstvo kultury|MK ČR|evidenční číslo periodického tisku|E\s*21743') { $memberships += "MKCR" }
    $orgText = if ($memberships.Count -gt 0) { ($memberships -join ",") } else { "none" }

    # 3. Security Headers
    $hasHsts = ($combinedHeaders -match 'strict-transport-security')
    $hasNosniff = ($combinedHeaders -match 'x-content-type-options:\s*nosniff')
    $hasXfo = ($combinedHeaders -match 'x-frame-options:\s*(sameorigin|deny)')
    $hasReferrer = ($combinedHeaders -match 'referrer-policy')
    $hasHttp3 = ($combinedHeaders -match 'alt-svc:.*h3')

    # 4. Schema.org JSON-LD Extraction
    $jsonMatches = [regex]::Matches($combinedHtml, '<script[^>]+type=["'']application/ld\+json["''][^>]*>([\s\S]*?)</script>')
    $jsonText = ""
    foreach ($m in $jsonMatches) { $jsonText += " " + $m.Groups[1].Value }

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
    if ($artHtml -match '<meta property="article:published_time" content="([^"]+)"') {
        $rawOg = $matches[1]
        if ($rawOg -match '([+-]\d{2}:\d{2})$') { $ogPubTz = $matches[1] }
        elseif ($rawOg -match 'Z$') { $ogPubTz = "Z" }
    }

    # OpenGraph & Twitter
    $ogType = if ($artHtml -match '<meta property="og:type" content="([^"]+)"') { $matches[1] } else { "none" }
    $ogImage = if ($artHtml -match '<meta property="og:image" content="([^"]+)"') { $matches[1] } else { "" }
    $imageFormat = "JPG"
    if ($ogImage -match '\.webp(\?.*)?$') { $imageFormat = "WebP" }
    elseif ($ogImage -match '\.avif(\?.*)?$') { $imageFormat = "AVIF" }
    elseif ($ogImage -match '\.png(\?.*)?$') { $imageFormat = "PNG" }

    $twitterCard = if ($artHtml -match '<meta name="twitter:card" content="([^"]+)"') { $matches[1] } else { "none" }

    # Robots & Discover
    $maxImagePreview = if ($artHtml -match 'max-image-preview:([^"''>,\s]+)') { $matches[1] } else { "none" }
    $hasDiscoverLarge = ($maxImagePreview -eq "large" -or $artHtml -match 'max-image-preview:large')

    # Performance, LCP, Speculation & Manifest
    $hasFetchPriorityHigh = ($artHtml -match 'fetchpriority=["'']high["'']' -or $hpHtml -match 'fetchpriority=["'']high["'']')
    $hasSpeculationRules = ($artHtml -match 'type=["'']speculationrules["'']' -or $hpHtml -match 'type=["'']speculationrules["'']' -or $combinedHeaders -match 'Speculation-Rules')
    $hasManifest = ($combinedHtml -match 'rel=["'']manifest["'']' -or $combinedHtml -match 'site\.webmanifest' -or $combinedHtml -match 'manifest\.json')
    $hasWebSub = ($combinedHtml -match 'rel=["'']hub["'']' -or $combinedHtml -match 'pubsubhubbub' -or $combinedHeaders -match 'rel="hub"')

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
    # Note: NO penalty for not having video/audio in a text article!
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

    if ($datePubTz -eq "+02:00") { $score += 6; $reasons += "+6b: Platná lokální zóna (+02:00)" }
    elseif ($datePubTz -match "Z|\+00:00") { $score += 3; $reasons += "+3b: UTC čas (zpoždění v Discover)" }

    if ($hasAuthorSameAs) { $score += 4; $reasons += "+4b: Sociální sítě autora" }
    if ($hasEditor) { $score += 4; $reasons += "+4b: Redakční garant (editor: $editorName)" }
    if ($hasMentions) { $score += 4; $reasons += "+4b: Sémantické entity (mentions: Thing)" }
    if ($hasSpeakable) { $score += 2; $reasons += "+2b: Google Assistant speakable" }

    # 3. OpenGraph & Discover (15 b)
    if ($ogType -eq "article") { $score += 4; $reasons += "+4b: og:type=article" }
    if ($ogPubTz -eq "+02:00") { $score += 4; $reasons += "+4b: OG publikováno v +02:00" }
    elseif ($ogPubTz -match "Z|\+00:00") { $score += 2; $reasons += "+2b: OG publikováno v UTC" }
    if ($twitterCard -eq "summary_large_image") { $score += 4; $reasons += "+4b: Twitter Large Card" }
    if ($hasDiscoverLarge) { $score += 3; $reasons += "+3b: max-image-preview:large" }

    # 4. Rychlost, WebSub & Moderní Web (15 b)
    if ($hasWebSub) { $score += 6; $reasons += "+6b: W3C WebSub Realtime Push Huby" }
    if ($hasHttp3) { $score += 3; $reasons += "+3b: HTTP/3 QUIC podpora" }
    if ($hasManifest) { $score += 2; $reasons += "+2b: Web Manifest & PWA" }
    if ($hasFetchPriorityHigh) { $score += 2; $reasons += "+2b: fetchpriority=high u LCP fotky" }
    if ($hasSpeculationRules) { $score += 2; $reasons += "+2b: Speculation Rules instant prerender" }

    # 5. Bezpečnost & Standardy (20 b)
    if ($hasHsts) { $score += 5; $reasons += "+5b: HSTS aktivní" }
    if ($hasNosniff) { $score += 5; $reasons += "+5b: X-Content-Type-Options nosniff" }
    if ($hasXfo) { $score += 4; $reasons += "+4b: X-Frame-Options ochrana" }
    if ($hasReferrer) { $score += 3; $reasons += "+3b: Referrer-Policy nastavena" }
    if ($h1Count -eq 1) { $score += 3; $reasons += "+3b: Čistá H1 hierarchie (1x H1)" }

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
        ProsCons       = $hasProsCons
        Speakable      = $hasSpeakable
        Timezone       = $datePubTz
        OgType         = $ogType
        OgImageFormat  = $imageFormat
        DiscoverLarge  = $hasDiscoverLarge
        FetchPriority  = $hasFetchPriorityHigh
        Speculation    = $hasSpeculationRules
        Manifest       = $hasManifest
        WebSub         = $hasWebSub
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
} else {
    Write-Host "Error: Template file $templateFile not found!"
}
