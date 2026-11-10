# mSTICK

Notes de bureau façon Notel (getnotel.app), en plus léger : chaque note est une vraie fenêtre sur le bureau. Swift, sans bac à sable,
sans fenêtre au lancement (`LSUIElement`) ; les notes ouvertes et les piles sont rouvertes à leur place.

- Interface : design system Socle. `Sources/mSTICK/Socle.swift`, `Updater.swift` et `UpdaterView.swift` sont recopiés par `build_app.sh`, ne pas les modifier ici.
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it) ; `swift test` vérifie que les 4 langues ont les mêmes clés.
- Cœur (`Sources/mSTICKCore`) : `Note` (rappels, flotter/coller/bureaux), `Vault` (un fichier AES-GCM par note, clé au Trousseau, marqueurs de suppression),
  `NoteStore` (enregistrement 250 ms après la dernière frappe, annulation de suppression), `SyncEngine` (dossier iCloud, `<id>.hmnote` en clair
  + `<id>.hmdeleted`, la plus récente gagne), `Exporter`, `MarkdownScanner`, `SmartCalc` (calculs et valeurs nommées, résultat en filigrane),
  `ReminderParser` (« remind me … » en fr/en/es/it).
- Design (repris de Notel) : carte arrondie sombre teintée de la couleur de la note, titre centré en couleur, croix de fermeture (8 styles, `CloseStyle`),
  barre de titre de 26 pt qui sert aussi de bande repliée dans une pile.
- Application : `NoteWindows` (une fenêtre par note, piles `NoteStack` : une note ouverte + barres des autres, Auto Stack au dépôt, Peek, sauvegarde de l'état),
  `NoteView`/`StickTextView` (éditeur Markdown en direct, filigrane Smart Calc, commandes `/` par la complétion native de NSTextView, rappels au retour chariot),
  `Fan` (éventail ⌥F, créé à l'ouverture et libéré à la fermeture), `Reminders` (un seul minuteur, sur le prochain rappel), `AllNotesView` (Bibliothèque),
  `SettingsView`, `HotkeyCenter` (Carbon, sans autorisation), icône de barre des menus monochrome (le menu s'ouvre à la main sous l'icône, jamais `statusItem.menu`).
- Données : `~/Library/Application Support/mSTICK` (`MSTICK_DATA_DIR`, `MSTICK_KEY_FILE` pour les essais).
- Essais sans fenêtre : `mSTICK --selftest` (éditeur, commandes /, Fan), `--demo --capture-note|-all|-settings|-about sortie.png` ; `--demo-notes` (notes en cascade et une pile), `--discret-ouvrir`,
  `--discret-toutes`, `--discret-reglages`, `--fan-ouvert` ouvrent les fenêtres sans prendre le focus.
- Build et installation : `./build_app.sh` ou `build_all.sh mSTICK`. Édition de test vierge : `MSTICK_EDITION=test ./build_app.sh`.
- Publier : `scripts/release.sh <version>` (notes dans `_tools/changelogs/mSTICK_<version>.txt`).
- Limites connues : tableaux Markdown en police fixe (pas de grille dessinée), pas d'image dans les notes, pas de récurrence des rappels, pas de Spring (bulles), de dossiers ni de verrouillage Touch ID (écartés pour rester léger).
