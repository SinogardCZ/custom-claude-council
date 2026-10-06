# Správce forku a postup vydání (SinogardCZ)

> Soubor vlastní tomuto forku (`SinogardCZ/custom-claude-council`, upstream `hex/claude-council`) — jméno se schválně
> nesrazí s žádným souborem upstreamu. Čtou ho Tom a AI persony všech projektů. Vznikl zadáním GSD TASK-155
> (2026-10-06); rozhodnutí, ze kterých plyne, jsou citovaná u každého bodu.

## Kdo council udržuje

- **Vlastník: Hestia GSD, vždy zadáním** — session Hestie projektu GSD s `--add-dir W:\dev\_shared\sinogard_ai_council`;
  platí její brány a review (rozhodl Tom, `ZCNC-Q4 = A`, 2026-09-30 09:14). Tom k tomu doslova:
  *„A - souhlasím, ale je potřeba to říci i ostatním, aby na to nesměli šáhnout pro úpravy."*
- **Ostatní projekty council jen používají.** Úpravu nedělají; požadavek jde **přes Toma** (`ZCNC-Q4`, `ZCNC-Q5`).
  Zapne-li council jiný projekt, přidá Tom v jeho session do jeho pojistky **zákaz zápisu** do
  `W:/dev/_shared/sinogard_ai_council/` (`ZCNC-Q5` ④).
- **Jediná pracovní kopie** je `W:/dev/_shared/sinogard_ai_council/` (`ZCNC-Q1 = A`). Projekty instalují **z forku na
  GitHubu** (marketplace `sinogard-council`, plugin `claude-council`) — změna se k nim dostane až commitem → push →
  aktualizací pluginu, ne úpravou této složky.

## Postup vydání

1. **Větev** z `main` (`feature/TASK-<n>-…`), zadání GSD.
2. **Testy forku** (`TESTING.md`): `bash tests/run_tests.sh` — sada je **bats**, na Windows běží pod Git Bash a potřebuje
   `bats` a `jq` (CI forku je instaluje `npm install -g bats` a `choco install jq`). ℹ️ K 2026-10-06 `bats` na Tomově PC
   nainstalovaný **není** (`which bats` = nic) — instalace nástroje je samostatný krok podle 7denního pravidla níž.
   Vydání, které mění jen dokumentaci, testy nespouští, ale řekne to.
3. **Review a brány** jako u každé změny Hestie GSD (persona GSD §11: `/code-review`, review Amber, GO Grace, kde ho zadání chce).
4. **Commit → merge `--no-ff` do `main` → push do `origin`.**
5. **V každém projektu, který council používá** (v jeho session):
   ```
   claude plugin marketplace update sinogard-council
   claude plugin update claude-council@sinogard-council
   ```
   Automatická aktualizace cizích marketplace je ve výchozím stavu **vypnutá** (docs
   `code.claude.com/docs/en/discover-plugins`, § Keep plugins updated / Manage marketplaces). Změna, která chování
   pluginu nemění (jen tento soubor), aktualizaci v projektech nepotřebuje.
6. **Řádek do sdíleného logu změn** `W:/dev/_shared/ai-changelog.md` — jen skriptem `zapis-zmeny.ps1` (`ZCNC-Q4`).

## Převzetí z upstreamu — 7 dní

Nová verze upstreamu se přebírá **až ve stáří ≥ 7 dní**, po review kódu na škodlivý obsah a kontrole proti internetu;
po převzetí nová analýza lokálních záplat (`ZOPT-Q24 = A`). Výjimka jen pro bezpečnostní opravu, která se týká našeho
použití (`ZOPT-Q50 = A`). Sync s upstreamem je **samostatné vydání**, ne vedlejší účinek jiné změny.

## Lokální záplaty (odchylky forku od upstreamu)

Nálezy v cizím kódu řešíme **jen lokální záplatou, autorům nic** (`ZOPT-Q25 = A`). Každá záplata má záznam
*kde · proč · proti které verzi · „neposílat"*. Stav 2026-10-06: `git log --oneline --no-merges upstream/main..main`
= přesně tři commity; `upstream/main` = `b09338f` (*Release v2026.9.2*, 2026-09-02, poslední fetch).

| Commit | Kde | Proč | Proti verzi upstreamu | Upstreamu |
|---|---|---|---|---|
| `80cc469` | `scripts/providers/nvidia.sh` (nový), `scripts/lib/providers.sh`, `scripts/check-status.sh`, testy | křeslo **NVIDIA NIM** (OpenAI-kompatibilní endpoint, klíč `NVIDIA_API_KEY`) — třetí výrobce modelu v councilu GSD | `b09338f` (v2026.9.2) | neposílat |
| `d2e5c5f` | `scripts/lib/tokens.sh` (`bump_for_reasoning --ceiling`), `tests/tokens.bats` | strop tokenů: endpoint s limitem pod podlahou 32768 (NVIDIA NIM `max_tokens` 1..16384) by jinak každé volání odmítl `400` | `b09338f` (v2026.9.2) | neposílat |
| `17e93a7` | `.claude-plugin/marketplace.json` | fork se ohlašuje jako marketplace `sinogard-council` — projekty instalují odsud | `b09338f` (v2026.9.2) | neposílat (patří jen forku) |

⚠️ Popis v `.claude-plugin/marketplace.json` (*„carrying changes that are open upstream as PRs"*) neodpovídá pravidlu
„autorům nic" — nahlášeno Tomovi v hlášení TASK-155, neopravuje se bez jeho slova.

## Klíče, cache, nastavení křesel

- ☢️ **Klíče nikdy do této složky ani do forku** (je to git klon veřejně hostovaného repa). Klíče patří **zvlášť do každého
  projektu**, který council zapne — do jeho `.claude/settings.local.json` mimo git; vkládá je Tom (`ZCNC-Q2 = A`).
- **Cache a přepisy councilu** (`.claude/council-cache/`, `council-*.md` s plným promptem) zůstávají **per projekt**
  a projekt je má v `.gitignore` — čitelný prompt jednoho projektu nepatří do sdílené složky (rozhodla Amber, zadání
  TASK-155 §2).
- **Modely křesel** (`GEMINI_MODEL`, `OPENROUTER_MODELS`, `NVIDIA_MODEL`, `COUNCIL_TIMEOUT` …) jsou **jednou
  v uživatelském nastavení** `~/.claude/settings.json` → `env`; projekt je smí přepsat ve svém nastavení (projekt má
  přednost); každá změna = řádek ve sdíleném logu (`ZCNC-Q3 = A`).

## CI forku

`.github/workflows/tests.yml` spouští **bats** (Linux, macOS, Windows) a **shellcheck** na `push` do `main`
a na `pull_request`. Stav 2026-10-06: Actions na forku **povolené** (`gh api repos/SinogardCZ/custom-claude-council/actions/permissions`
→ `enabled: true`), workflow `tests` **aktivní** — ale historie běhů je **prázdná** (`gh run list -R SinogardCZ/custom-claude-council`
→ `[]`), takže verdikt CI forku zatím neexistuje. Push větve běh nespustí (trigger je jen `main` a PR); první běh čekej
po pushi `main`. Verdikt se čte `gh run list -R SinogardCZ/custom-claude-council` / `gh run view <id>`.
