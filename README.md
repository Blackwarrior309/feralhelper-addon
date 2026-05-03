# FeralHelper

WoW 3.3.5a Addon für Feral Druiden (Katze & Bär). Trackt Cooldowns, Procs und defensive Fähigkeiten in Echtzeit.

---

## Features

### CD-Tracker Leiste (15 Slots)

| Icon | Funktion | Klickbar |
|------|----------|----------|
| Baumrinde | CD-Anzeige | — |
| Berserk | CD-Anzeige | ✓ Selbst-Cast |
| Tigerwut / Rasende Regen. | Katze/Bär (gleicher Slot) | ✓ Selbst-Cast |
| Überlebensinstinkte | CD-Anzeige | ✓ Selbst-Cast |
| Anregen | CD-Anzeige | ✓ wirkt auf Ziel + Whisper |
| Wiedergeburt | CD-Anzeige | ✓ wirkt auf totes Ziel |
| Trinket 1 & 2 | Proc grün / ICD gedimmt | — |
| Hyperspeed (Handschuhe) | Proc-Erkennung | ✓ Aktiviert Item |
| Nitro Boots (Schuhe) | Proc-Erkennung | ✓ Aktiviert Item |
| Waffe VZ | Zeigt aktiven Waffenproc mit dynamischem Icon | — |
| Mantel VZ | Zeigt aktiven Schneider-Mantel-Proc mit dynamischem Icon | — |
| Ring 1 & 2 | Nur bei Ashen Band equipped | — |
| Panik-Knopf | Bär + Baumrinde + Wutanfall + ÜberInst in 1 Klick | ✓ |

### Waffen-VZ Proc-Erkennung (1 kombinierter Slot)

Erkennt automatisch welcher Waffenproc gerade aktiv ist und zeigt dessen Icon:

- Black Magic (ICD 35s)
- Berserker, Mongoose, Vollstrecker, BlutAbzug, Kreuzritter (ICD 0s)

### Mantel-VZ Proc-Erkennung (1 kombinierter Slot)

- Lightweave (ICD 60s)
- Schwertwallgarn (ICD 55s)

### Trinket-Proc-Tracking

Unterstützt über 100 WotLK-Trinkets mit korrekten ICDs, darunter:

- Deathbringer's Will (ICD 105s)
- Phylactery of the Nameless Lich (ICD 100s)
- Charred Twilight Scale (ICD 50s)
- Death's Verdict / Choice, Whispering Fanged Skull, DFO, Muradin's Spyglass, u.v.m.
- Ältere Trinkets (Ulduar, ToC, Naxx, TBC, Classic)

### Ashen Band (ICC Ruf-Ring)

Alle 10 Varianten automatisch erkannt (Slot 11 & 12), ICD 60s.

### Weitere Frames

| Frame | Funktion |
|-------|----------|
| Hysteria-Frame | Buff-Dauer + 180s CD + Auto-Whisper bei Kampfbeginn |
| HoP-Button | Erscheint wenn Hand des Schutzes aktiv → Klick entfernt Buff |
| Freizaubern | Erscheint bei Omen of Clarity Proc |
| Roar+Rip Warnung | Warnt wenn Savage Roar + Rip gleichzeitig ablaufen |
| Rip Snapshot | Rip-Restdauer + Snapshot-Vergleich + Recast-Empfehlung |

### Rip Snapshot

Speichert beim Rip-Cast die aktuellen Schadensmultiplikatoren und vergleicht sie live mit dem laufenden Rip:

| Faktor | Einfluss |
|--------|---------|
| Tiger's Fury (TF) | +15% Schaden |
| Savage Roar (SR) | +30% physischer Schaden |
| Hysteria (H) | +20% physischer Schaden |
| Tricks of the Trade (T) | +15% Schaden |
| Mangle/Trauma-Debuff (M) | +30% Bleed-Schaden |
| Attack Power (AP) | Schwelle: +300 AP |

Das Frame zeigt zwei Statuszeilen:

```
S TF+SR-H-T-M+  4520      ← Snapshot beim Cast
C TF+SR+H+T-M+  5100 +580 ← Aktuelle Werte
```

Sobald aktuelle Werte besser sind:
- **`↑ NEU RIP: Xs`** (gold) — Rip noch > 5s, Recast empfohlen, Countdown zeigt wie lange der Vorteil besteht
- **`↑ JETZT CASTEN!`** (orange) — Rip ≤ 5s, sofort neu casten

---

## Slash Commands

| Befehl | Funktion |
|--------|----------|
| `/fh` | Einstellungen öffnen |
| `/fh reset` | Alle Frame-Positionen zurücksetzen |
| `/fh icons` | Icon-Test: alle Icons sichtbar (Toggle) |
| `/fh test` | Roar+Rip und Rip-Snapshot Test-Ansicht |
| `/fh debug` | Debug-Info: Formstatus, Buff-Zeiten |

---

## Installation

1. Ordner `feralhelper-addon-master` nach `World of Warcraft/Interface/AddOns/` kopieren
2. Spiel starten oder `/reload` eingeben
3. Nur für Druiden aktiv — bei anderen Klassen deaktiviert

---

## Konfiguration

- Minimap-Icon **Linksklick** → Einstellungen (`/fh`)
- Minimap-Icon **Rechtsklick** → Frames sperren/entsperren
- Minimap-Icon **Ziehen** → Position anpassen
- Alle Frames sind per Drag verschiebbar (solange nicht gesperrt)

---

## Struktur

```
feralhelper-addon-master/
├── FeralHelper.lua          # Hauptlogik, Events, CD-Tracker
├── Config.lua               # Einstellungen, Config-Frame
├── feralhelper-addon-master.toc
└── TrinketCDs/              # Proc-Datenbank (IDs + ICDs)
    ├── TrinketCDsDB.lua
    ├── TrinketCDs.lua
    └── ...
```

---

## Kompatibilität

- WoW **3.3.5a** (Wrath of the Lich King)
- Getestet auf rising-gods.de
- Funktioniert sprachunabhängig via `GetSpellInfo()` (DE/EN/etc.)
