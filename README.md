🐾 FeralHelper

FeralHelper ist ein World of Warcraft Addon, das speziell für Feral Druiden (Katze/Bär) entwickelt wurde.
Es hilft dir, wichtige Cooldowns, Procs und defensive Fähigkeiten im Blick zu behalten – für bessere Entscheidungen im Kampf.

✨ Features
🧠 Automatisches Tracking wichtiger Fähigkeiten
Tiger's Fury
Berserk
Barkskin
Survival Instincts
Innervate
Rebirth
⚡ Proc-Erkennung
Clearcasting (Omen of Clarity)
Trinket-Procs (inkl. ICC-Trinkets)
⏱️ Interne Cooldowns (ICD)
Unterstützt bekannte WotLK-Trinkets
Eigene Timer nach Proc-Ende
🛡️ Defensive Cooldowns im Blick
Barkskin
Bear Form + Enrage
Survival Instincts
🌍 Mehrsprachige Unterstützung
Nutzt GetSpellInfo() → funktioniert unabhängig von Client-Sprache (DE/EN/etc.)
📦 Installation
Lade das Addon herunter
Entpacke es in deinen WoW Addons-Ordner:
World of Warcraft/_classic_/Interface/AddOns/FeralHelper
Starte das Spiel neu oder tippe:
/reload
📁 Struktur
FeralHelper/
├── FeralHelper.lua   # Hauptlogik
├── Config.lua        # Einstellungen / Konfiguration
├── FeralHelper.toc   # Addon-Definition
⚙️ Konfiguration

Die Einstellungen befinden sich aktuell in:

Config.lua

Hier kannst du z.B. anpassen:

Welche Spells überwacht werden
Cooldowns / Timer
Anzeigeverhalten (je nach Erweiterung)
🧩 Unterstützte Trinkets (Beispiele)
Death's Verdict / Choice
Whispering Fanged Skull
Needle-Encrusted Scorpion
Mjolnir Runestone

👉 Alle mit internen Cooldowns (ICD Tracking)

🚧 Geplante Features
UI / Anzeige (Icons, Bars, Alerts)
Slash Commands (/fh)
WeakAura-ähnliche Visualisierung
Benutzerfreundliche Einstellungen im Spiel
Erweiterte Rotation-Hilfe
🛠️ Entwicklung

Das Addon ist modular aufgebaut:

Core (FeralHelper.lua)
→ Logik, Events, Tracking
Config.lua
→ zentrale Einstellungen
🤝 Mitwirken

Pull Requests und Ideen sind willkommen!

Wenn du Bugs findest oder Features willst:
→ Issue erstellen 👍

📜 Lizenz

Freie Nutzung für private Zwecke.
Anpassungen erlaubt.
