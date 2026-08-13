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

### 1. 🏛️ Vydavatel & E-E-A-T (Max 25 bodů)
- `NewsMediaOrganization` = **10 b** (`Organization` = 5 b, Žádná = 0 b)
- Redakční zásady a tiráž (`ethicsPolicy` + `masthead`) = **6 b** (částečné = 3 b)
- Poštovní adresa (`PostalAddress`) = **3 b**
- Registrace ISSN (`issn`) = **2 b**
- 5+ sociálních profilů (`sameAs`) = **4 b** (1–4 = 2 b)

### 2. 📰 Článek & Autoři (Max 30 bodů)
- Schéma článku `NewsArticle` = **10 b** (`Article` = 5 b, `BlogPosting` = 3 b)
- Lokální časové pásmo `+02:00` = **6 b** (`Z` / `+00:00` = 3 b)
- Sociální sítě autora (`sameAs`) = **4 b**
- Redakční garant (`editor`) = **4 b**
- Sémantické entity štítků (`mentions: Thing`) = **4 b**
- Hlasoví asistenti (`speakable`) = **2 b**

### 3. 🌐 OpenGraph & Metadata (Max 15 bodů)
- `og:type: article` = **5 b** (`website` = 2 b)
- `article:published_time` s lokálním offsetem `+02:00` = **5 b** (GMT = 2 b)
- `twitter:card: summary_large_image` = **5 b** (`summary` = 2 b)

### 4. ⚡ Indexace & Rychlost (Max 15 bodů)
- W3C WebSub Realtime Push Huby (`rel="hub"`) = **10 b**
- Velikost HTML článku do 250 kB = **5 b** (do 500 kB = 3 b, nad 500 kB = 1 b)

### 5. 🛡️ Bezpečnostní HTTP hlavičky (Max 15 bodů)
- `Strict-Transport-Security` (HSTS) = **4 b**
- `X-Content-Type-Options: nosniff` = **4 b**
- `X-Frame-Options` = **4 b**
- `Referrer-Policy` = **3 b**
