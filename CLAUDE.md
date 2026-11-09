# mSTICK

Version personnelle de Hold My Notes (holdmynotes.app) : notes adhésives dans un « deck » au bord de l'écran. Swift, sans bac à sable,
sans fenêtre au lancement (`LSUIElement`).

- Interface : design system Socle. `Sources/mSTICK/Socle.swift`, `Updater.swift` et `UpdaterView.swift` sont recopiés par `build_app.sh`, ne pas les modifier ici.
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it) ; `swift test` vérifie que les 4 langues ont les mêmes clés.
- Cœur (`Sources/mSTICKCore`) : `Note`, `Vault` (un fichier AES-GCM par note, clé au Trousseau, marqueurs de suppression), `NoteStore`
  (enregistrement 250 ms après la dernière frappe, annulation de suppression), `SyncEngine` (dossier iCloud, `<id>.hmnote` en clair
  + `<id>.hmdeleted`, la plus récente gagne), `Exporter` (.md, .txt, fichier unique, .stickies, dossier Markdown), `MarkdownScanner`.
- Design (repris de holdmynotes.app) : repos = capsule sombre avec une pastille par note ; survol = cartes en écailles (étiquette verticale en majuscules, perforation en pointillés, 45 ms entre deux) ; ouverture = la même carte, qui glisse hors du deck, étiquette du côté du deck, police manuscrite. Le deck est dessiné une fois côté droit puis tourné (`DeckView`). Pendant le glissement de la poignée, `DropZones` allume l'écran et le bord visés (`DeckTarget.resolve`).
- Application : `Deck.swift` (une fenêtre par écran), `NoteWindows`/`NoteView`/`StickTextView` (éditeur Markdown
  en direct), `AllNotesView`, `SettingsView`, `HotkeyCenter` (Carbon, sans autorisation), icône de barre des menus monochrome
  (le menu s'ouvre à la main sous l'icône, jamais `statusItem.menu`).
- Données : `~/Library/Application Support/mSTICK` (`MSTICK_DATA_DIR`, `MSTICK_KEY_FILE` pour les essais).
- Essais sans fenêtre : `mSTICK --selftest` (éditeur), `--demo --capture-note|-all|-settings|-deck|-about sortie.png` ; `--discret-ouvrir`,
  `--discret-toutes`, `--discret-reglages`, `--deck-ouvert` ouvrent les fenêtres sans prendre le focus.
- Build et installation : `./build_app.sh` ou `build_all.sh mSTICK`. Édition de test vierge : `MSTICK_EDITION=test ./build_app.sh`.
- Publier : `scripts/release.sh <version>` (notes dans `_tools/changelogs/mSTICK_<version>.txt`).
- Limites connues : tableaux Markdown en police fixe (pas de grille dessinée), pas de barre flottante sur sélection, pas d'image dans les notes.
