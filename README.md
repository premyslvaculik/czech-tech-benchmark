# Benchmark & SEO Audit System pro Dotekománie.cz

Tento modul slouží k pravidelnému, 100% automatizovanému a objektivnímu porovnání technologické a SEO připravenosti **16 předních českých tech médií**.

---

## 📂 Struktura složky `benchmark/`

```text
benchmark/
├── 2026-08-11.html                 # Interaktivní HTML report pro konkrétní datum
├── targets.txt                     # Textový seznam sledovaných médií (lze jednoduše přidávat další)
├── data/
│   ├── raw-audit-2026-08-11.json   # Kompletní surová JSON data z živých webů
│   └── scored-2026-08-11.json      # Vypočtená skóre a detailní bodové rozpadnutí
├── scripts/
│   └── run-audit.ps1               # PowerShell skript pro spuštění nového auditu
└── README.md                       # Tato dokumentace a metodika bodování
```

---

## ➕ Jak jednoduše přidat nový web do sledování:

Otevřete soubor **`benchmark/targets.txt`** a na nový řádek přidejte požadovaný web.  
Můžete zadat buď jen název a adresu webu (skript si sám dohledá RSS a nejnovější článek), nebo kompletní řádek:

```text
NazevWebu | https://domena.cz/ | https://domena.cz/feed/ | https://domena.cz/clanek-ukazkovy
```

---

## 🚀 Jak vygenerovat novou analýzu pro nové datum:

Pro spuštění nového živého auditu stačí v terminálu spustit:

```powershell
powershell -ExecutionPolicy Bypass -File "benchmark/scripts/run-audit.ps1"
```

Skript automaticky:
1. Projde všech 16 webů (hlavní stránku i nejnovější článek).
2. Otestuje všechna Schema.org, OpenGraph, WebSub, HTTP hlavičky a časové zóny.
3. Uloží nová JSON data do `benchmark/data/`.
4. Vygeneruje nový interaktivní HTML soubor pojmenovaný podle aktuálního data (např. `benchmark/2026-09-01.html`).

---

## ⚖️ Metodika bodování (Max 100 bodů)

### 1. 🏛️ Vydavatel & E-E-A-T (Max 20 bodů)
- Schéma vydavatele: `NewsMediaOrganization` = **8 b** (`Organization` = 4 b, Žádná = 0 b)
- Redakční zásady a tiráž (`ethicsPolicy` + `masthead`) = **5 b** (částečné = 2 b)
- Poštovní adresa sídla (`PostalAddress`) = **3 b**
- Registrace periodického tisku ISSN = **2 b**
- Oborové členství (ČUV, AOV, SPIR, Syndikát novinářů) = **2 b**

### 2. 📰 Článek & Autoři (Max 30 bodů)
- Schéma článku: `NewsArticle` = **10 b** (`Article` = 5 b, `BlogPosting` = 3 b)
- Lokální časové pásmo `+02:00` / `+01:00` = **6 b** (`Z` / `+00:00` UTC = 3 b)
- Sociální sítě autora (`sameAs`) = **4 b**
- Redakční garant (`editor`) = **4 b**
- Sémantické entity štítků (`mentions: Thing`) = **4 b**
- Hlasoví asistenti (`speakable`) = **2 b**

### 3. 🌐 OpenGraph & Discover (Max 15 bodů)
- `og:type: article` = **4 b**
- `article:published_time` v lokálním čase = **4 b** (UTC = 2 b)
- `twitter:card: summary_large_image` = **4 b**
- `max-image-preview:large` (Google Discover) = **3 b**

### 4. ⚡ Rychlost, WebSub & Moderní Web (Max 20 bodů)
- W3C WebSub Realtime Push Huby (`rel="hub"`) = **5 b**
- HTTP/3 (QUIC) podpora serveru = **3 b**
- Validní XML feed (`Content-Type: application/rss+xml` / `atom+xml`) = **2 b**
- Preconnect & DNS-Prefetch optimalizace pro kritické domény = **2 b**
- PWA Web Manifest (`site.webmanifest` / `manifest.json`) = **2 b**
- LCP priorita obrázku (`fetchpriority="high"`) = **2 b**
- Okamžitý prerender (`Speculation Rules API`) = **2 b**
- Fediverse Creator podpora (`<meta name="fediverse:creator">`) = **2 b**

### 5. 🛡️ Bezpečnost & Standardy (Max 15 bodů)
- `Strict-Transport-Security` (HSTS) = **4 b**
- `X-Content-Type-Options: nosniff` = **3 b**
- `X-Frame-Options` (Sameorigin / Deny) = **3 b**
- Sitemap XML dostupná a deklarovaná v `robots.txt` = **2 b**
- Oficiální W3C HTML5 Validita (0 chyb na `validator.w3.org`) = **3 b** (či 1× H1 = 2 b)
