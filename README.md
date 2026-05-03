# FeralHelper

WoW 3.3.5a Addon fuer Feral Druiden (Katze und Baer). Trackt Cooldowns, Procs, defensive Faehigkeiten und Rip-Snapshots in Echtzeit.

---

## Features

### CD-Tracker Leiste

| Icon | Funktion | Klickbar |
|------|----------|----------|
| Baumrinde | CD-Anzeige | nein |
| Berserk | CD-Anzeige | Selbst-Cast |
| Tigerwut / Rasende Regeneration | Katze/Baer im gleichen Slot | Selbst-Cast |
| Ueberlebensinstinkte | CD-Anzeige | Selbst-Cast |
| Anregen | CD-Anzeige | wirkt auf Ziel + Whisper |
| Wiedergeburt | CD-Anzeige | wirkt auf totes Ziel |
| Trinket 1 und 2 | Proc-Dauer gruen / ICD gedimmt | nein |
| Hyperspeed (Handschuhe) | Proc-Erkennung | aktiviert Item |
| Nitro Boots (Schuhe) | Proc-Erkennung | aktiviert Item |
| Waffe VZ | Aktiver Waffenproc mit dynamischem Icon | nein |
| Mantel VZ | Aktiver Schneider-Mantel-Proc mit dynamischem Icon | nein |
| Ring 1 und 2 | Ashen-Band-Procs | nein |
| Panik-Knopf | Baer + Baumrinde + optional Wutanfall + Ueberlebensinstinkte | ja |

### Waffen-VZ Proc-Erkennung

Erkennt automatisch, welcher Waffenproc gerade aktiv ist:

- Black Magic (ICD 35s)
- Berserker, Mongoose, Vollstrecker, BlutAbzug, Kreuzritter

### Mantel-VZ Proc-Erkennung

- Lightweave (ICD 60s)
- Schwertwallgarn (ICD 55s)

### Trinket-Proc-Tracking

Unterstuetzt viele WotLK-Trinkets mit ICDs, darunter:

- Deathbringer's Will
- Phylactery of the Nameless Lich
- Charred Twilight Scale
- Death's Verdict / Choice
- Whispering Fanged Skull
- Dislodged Foreign Object
- Muradin's Spyglass
- aeltere Trinkets aus Ulduar, ToC, Naxx, TBC und Classic

Wenn ein Trinket im Snapshot-Fenster als `?` angezeigt wird, kennt das Addon den Proc noch nicht. Dann muessen ItemID und Buff-SpellID ergaenzt werden.

Der synthetische ICD startet beim Proc-Start und laeuft im Hintergrund weiter. Solange der Proc aktiv ist, zeigt das Icon die Proc-Restdauer. Sobald der Proc endet, schaltet die Anzeige auf den bereits heruntergezaehlten ICD um.

### Panik-Knopf

Der Panik-Knopf wirkt Baerengestalt, entfernt Hysteria, wirkt Baumrinde und danach Ueberlebensinstinkte. Wutanfall wird nur in das Macro aufgenommen, wenn mindestens 4 Teile des Feral-T10-Sets `Lasherweave Battlegear` getragen werden. Ohne diesen Setbonus wird Wutanfall ausgelassen, damit der Armor-Nachteil nicht versehentlich im Panik-Macro landet.

Das Panik-Icon zeigt `T10`, wenn der 4er erkannt wurde. Der Tooltip und `/fh debug` zeigen ebenfalls, ob Wutanfall im Macro aktiv ist.

### Weitere Frames

| Frame | Funktion |
|-------|----------|
| Hysteria-Frame | Buff-Dauer + 180s CD + Auto-Whisper bei Kampfbeginn |
| HoP-Button | Erscheint auch im Kampf bei Hand des Schutzes; Klick entfernt Buff |
| Freizaubern | Erscheint bei Omen-of-Clarity-Proc |
| Roar+Rip Warnung | Experimentell; warnt, wenn Savage Roar und Rip gleichzeitig ablaufen |
| Rip Snapshot | Experimentell; Rip-Restdauer, Snapshot-Vergleich, Pull-Modus und Recast-Empfehlung |

---

## Rip Snapshot (experimentell)

Standardmaessig deaktiviert. Aktivierbar ueber `/fh` unter Katzenrotation.

Speichert beim Rip-Cast die aktuellen Snapshot-Faktoren und vergleicht sie live mit den aktuellen Werten.

| Faktor | Anzeige | Bedeutung |
|--------|---------|-----------|
| Tiger's Fury | TF | +15% Schaden |
| Savage Roar | SR | +30% physischer Schaden |
| Hysteria | H | +20% physischer Schaden |
| Tricks of the Trade | T | +15% Schaden |
| Mangle/Trauma | M | +30% Bleed-Schaden |
| Trinket 1/2 | T1/T2 | erkannte aktive Trinket-Procs |
| Attack Power | AP | Recast-Schwelle: +300 AP |

Das Frame zeigt Snapshot und aktuelle Werte:

```text
S TF+SR-H-T-M+  4520
C TF+SR+H+T-M+  5100 +580
```

### Recast-Anzeigen

- `NEU RIP: Xs`: aktuelle Werte sind besser; Countdown zeigt, wie lange der Vorteil noch besteht.
- `JETZT: Xs`: Rip ist im Recast-Fenster und der bessere Snapshot laeuft in X Sekunden aus.
- `NEU RIP (AP)`: AP ist besser, aber fuer den Vorteil ist keine sichere Ablaufzeit bekannt.

Der Countdown beruecksichtigt Tigerwut, Savage Roar, Hysteria, Tricks und erkannte Trinket-Procs. Wenn ein Buff oder Proc auslaeuft und der Snapshot dadurch schlechter wird, zeigt das Frame die verbleibende Zeit bis zu diesem Ablauf. Eine kurze Ursachenzeile zeigt, warum ein neuer Rip besser waere, z.B. `TF Trinket AP+500`.

---

## Pull-Modus (experimentell)

Standardmaessig deaktiviert, weil er Teil der Rip-Snapshot-Anzeige ist.

Beim Kampfbeginn wird das Rip-Snapshot-Fenster sichtbar, auch wenn noch kein Rip aktiv ist.

Der Pull-Modus startet nur, wenn Trinket 1 und Trinket 2 nicht auf CD sind. Danach zeigt das Fenster:

- `T1 ready` / `T2 ready`: Trinket bereit
- `T1 CD12`: Trinket oder synthetischer ICD laeuft noch 12 Sekunden
- `T1 P8`: Trinket-Proc ist aktiv und laeuft in 8 Sekunden aus
- `T1 ?`: Trinket-Proc ist dem Addon unbekannt
- aktuelle Buffs: TF, SR, H, T, M und AP

Das Addon wartet am Pull bis zu 8 Sekunden auf fruehe Procs oder Buffs. Sobald ein wertvoller Snapshot aktiv ist, zeigt es:

```text
RIP!
RIP snapshot: 6s
```

Die grosse Zahl im Rip-Icon zeigt dann ebenfalls die Restzeit des hoechsten Snapshot-Fensters.

---

## Slash Commands

| Befehl | Funktion |
|--------|----------|
| `/fh` | Einstellungen oeffnen |
| `/fh reset` | Alle Frame-Positionen zuruecksetzen |
| `/fh defaults` | Standard-Einstellungen laden, Positionen behalten |
| `/fh icons` | Icon-Test: alle Icons sichtbar |
| `/fh test` | Roar+Rip und Rip-Snapshot Test-Ansicht |
| `/fh debug` | Debug-Info: Formstatus, Buff-Zeiten |

---

## Installation

1. Ordner `feralhelper-addon-master` nach `World of Warcraft/Interface/AddOns/` kopieren.
2. Spiel starten oder `/reload` eingeben.
3. Das Addon ist nur fuer Druiden aktiv.

---

## Konfiguration

- Minimap-Icon Linksklick: Einstellungen (`/fh`)
- Minimap-Icon Rechtsklick: Frames sperren/entsperren
- Minimap-Icon ziehen: Position anpassen
- Alle Frames sind per Drag verschiebbar, solange sie nicht gesperrt sind.
- `Frames anzeigen`: blendet Positions-Frames kurz als Vorschau ein.
- Button `Standard laden` oder `/fh defaults`: setzt raid-sichere Standardwerte und behaelt Frame-Positionen.

### Standardwerte

- Anzeige aktiv: Hysteria-Frame, Clearcast-Frame, CD-Leiste
- Experimentell und standardmaessig aus: Roar+Rip-Warnung, Rip-Snapshot/Pull-Modus
- Automatische Kampf-/CD-Whisper fuer Boesartigkeit: aus
- Whisper per Klick auf das Hysteria-Frame: an
- Anregen-Whisper beim Cast: an
- Automatische `/sagen`-Meldungen: aus
- Frames: entsperrt

---

## Struktur

```text
feralhelper-addon-master/
|-- FeralHelper.lua
|-- Config.lua
|-- feralhelper-addon-master.toc
`-- README.md
```

---

## Kompatibilitaet

- WoW 3.3.5a (Wrath of the Lich King)
- Getestet auf rising-gods.de
- Lokalisierte Spellnamen werden ueber `GetSpellInfo()` aufgeloest
