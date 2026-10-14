# Notchling

Notchling ist eine native Menüleisten-App für das MacBook Pro mit Notch. Ein randloses Panel liegt über der Notch, klappt bei Hover oder Klick mit einer Feder-Animation auf und zeigt Wiedergabe, Termine, eine Dateiablage, den Akku und auf Wunsch einen Kamera-Spiegel.

Die App ist eine eigenständige Neuimplementierung in Swift, SwiftUI und AppKit. Sie enthält keinen Code aus NotchNook und keinen Code aus boring.notch. boring.notch (GPL-3.0) diente höchstens als Orientierung für die Art der Funktionen, nicht als Quelle. Deshalb steht Notchling unter der MIT-Lizenz, siehe [LICENSE](LICENSE).

[![Build](https://github.com/gitmomo23/NotchApp/actions/workflows/build.yml/badge.svg)](https://github.com/gitmomo23/NotchApp/actions/workflows/build.yml)

## Voraussetzungen

- Mac mit Apple Silicon (der Build ist arm64)
- macOS 26 oder neuer
- Für die echte Notch-Geometrie ein MacBook Pro mit Notch. Auf anderen Macs setzt sich Notchling als Insel oben in die Mitte des Bildschirms.

## Installation

1. Lade `Notchling.dmg` aus den [Releases](https://github.com/gitmomo23/NotchApp/releases) oder aus den Build-Artefakten.
2. Öffne das DMG und ziehe `Notchling.app` in den Ordner **Programme**.
3. Die App ist nur ad-hoc signiert und nicht notarisiert. macOS blockiert den ersten Start aus dem Download.

So startest du sie trotzdem:

- **Rechtsklick** auf `Notchling.app` → **Öffnen** → im Dialog noch einmal **Öffnen**.
- Oder im Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Notchling.app
```

Dieselbe App steckt auch in `Notchling.zip`, falls du kein DMG verwenden willst. Für den Start beim Anmelden sollte die App in `/Applications` liegen.

## Bedienung

Das Menüleisten-Symbol ist immer da. Sein Menü beginnt mit **Panel öffnen**. Hover über die Pille unter der Notch klappt das Panel auf, solange „Beim Darüberfahren öffnen“ aktiv ist. Es bleibt offen, solange der Zeiger im aufgeklappten Bereich ist, und schließt erst etwa 0,4 Sekunden nachdem der Zeiger diesen Bereich wirklich verlassen hat. Ein Klick auf die Pille pinnt das Panel, bis außerhalb geklickt wird. Die Stecknadel hält es offen, der Pfeil nach oben schließt es. Escape schließt es, wenn das Panel Tastaturfokus hat. Beim Start klappt das Panel einmal kurz auf, damit sichtbar ist, dass es läuft.

In den Einstellungen schaltest du einzelne Funktionen und den Start beim Anmelden.

## Funktionen

- **Notch-Panel.** Randloses `NSPanel` über der Menüleiste, Feder-Animation, Hover und Klick. Zugeklappt bleibt eine kleine Pille unter der Notch sichtbar.
- **Wiedergabe.** Cover, Titel, Play/Pause, Titelwechsel und Fortschritt. Zuerst die Systemwiedergabe (MediaRemote, zur Laufzeit geladen). Wenn die nichts liefert, AppleScript für Musik (`com.apple.Music`) und Spotify (`com.spotify.client`).
- **Kalender.** Die nächsten Termine über EventKit, mit explizitem Zugriffsdialog.
- **Dateiablage.** Dateien per Drag-and-drop ablegen, persistent als Lesezeichen, wieder herausziehen, per AirDrop oder dem Teilen-Dialog (`NSSharingService`) verschicken. Rechtsklick auf ein Symbol.
- **Akku.** Ladestand und Ladezustand über die öffentliche IOKit-Power-Source-API.
- **HUD.** Ersetzt Lautstärke- und, soweit der Mac sie freigibt, Helligkeitstasten. Abschaltbar. Standard ist aus.
- **Spiegel.** Lokale Kameravorschau über AVFoundation, gespiegelt, nur solange das Panel offen und der Spiegel eingeschaltet ist.
- **Einstellungen.** Feature-Schalter und Start beim Anmelden über `SMAppService`.
- **Menüleiste.** `LSUIElement`, kein Dock-Symbol, Status-Icon mit dem Eintrag „Panel öffnen“. Usage-Strings für Kamera, Kalender und Apple Events stehen in `Notchling/Info.plist`.

## Berechtigungen

| Aktion | Systemdialog |
| --- | --- |
| Termine | Kalender, voller Zugriff |
| Spiegel | Kamera |
| Musik/Spotify-Fallback | Automatisierung |
| HUD-Ersatz | Bedienungshilfen |

Die Kamera geht erst an, wenn du den Spiegel einschaltest. Kalender und Bedienungshilfen fragen erst, wenn du die Funktion auslöst.

## Bauen

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open Notchling.xcodeproj
```

Deployment-Target ist macOS 26, Architektur arm64. Der GitHub-Actions-Workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) läuft auf `macos-26` mit dem aktuellen Xcode-26-SDK, baut Release, signiert ad-hoc (`codesign -s -`), packt `Notchling.dmg` und `Notchling.zip` und lädt sie als Artefakt hoch. Ein Tag `v*` veröffentlicht ein GitHub-Release mit beiden Dateien.

## Einschränkungen

- Ad-hoc-Signatur, keine Notarisierung. Gatekeeper verlangt Rechtsklick → Öffnen oder das Entfernen der Quarantäne.
- Nur arm64. Kein Intel-Build.
- MediaRemote ist eine private Systemschnittstelle und kann nach einem macOS-Update leer bleiben oder verschwinden. Dann gilt der AppleScript-Fallback, und der gilt nur für Musik und Spotify.
- Andere Player erscheinen nur, wenn MediaRemote sie liefert. Artwork gibt es im AppleScript-Fallback nicht.
- Der Kalenderdialog braucht kurz eine normale Aktivierung (Dock-Symbol), weil macOS den Zugriff von reinen Menüleisten-Apps sonst nicht zeigt. Danach ist die App wieder ein Accessory.
- Die Dateiablage speichert Sicherheitslesezeichen unter `~/Library/Application Support/Notchling/`. Gelöschte oder verschobene Dateien lassen sich nicht mehr öffnen und können entfernt werden.
- AirDrop muss auf dem Mac verfügbar sein. Sonst öffnet sich der normale Teilen-Dialog.
- Ohne internen Akku (Mac mini, Studio) bleibt die Akkuzeile leer.
- Lautstärke läuft über CoreAudio. Helligkeit läuft über IOKit und, falls nötig, die private DisplayServices-Schnittstelle. Auf manchen Apple-Silicon-Macs ist die Helligkeit nicht lesbar; dann bleiben die Helligkeitstasten beim System.
- Die System-HUD verschwindet nur, wenn Bedienungshilfen erlaubt sind und Notchling die Taste selbst verarbeitet. Ohne diese Erlaubnis zeigt macOS seine HUD weiter, und Notchling kann zusätzlich eine eigene anzeigen. Die Funktion ist standardmäßig aus.
- Ein fehlgeschlagener Helligkeits-Probe wird gespeichert und danach nicht mehr versucht, damit ein Absturz in der privaten Schnittstelle sich nicht bei jedem Start wiederholt.
- Der Spiegel ist eine lokale Vorschau, kein Effekt-Spiegel. Die Kamera-LED leuchtet. Es wird nichts gespeichert oder gesendet. Beim Zuklappen stoppt die Aufnahme.
- `SMAppService` kann eine zusätzliche Bestätigung unter „Anmeldeobjekte & Erweiterungen“ verlangen.
- Kein Sandbox, kein Auto-Update, kein Mac-App-Store-Build.
- Die Notch-Maße kommen aus `safeAreaInsets` und `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Die geschlossene Pille hängt zusätzlich etwa 22 Punkte unter die Menüleiste, weil die Notch selbst keine Pixel hat. Sitzt das Panel daneben, kopiert der Menüpunkt „Bildschirmgeometrie kopieren“ die gemessenen Rechtecke. Diagnose: `log stream --predicate 'subsystem == "com.notchling.app"' --level notice`.

## Projektlayout

`project.yml` ist die XcodeGen-Quelle. `scripts/ci-build.sh` ist der Release-Pfad, den die Action ausführt. `scripts/make-icon.py` zeichnet das App-Icon neu.
