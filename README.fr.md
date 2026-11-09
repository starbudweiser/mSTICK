# mSTICK

[English](README.md)

Notes adhésives rangées au bord de l'écran, chiffrées et toujours à portée de main. Version personnelle inspirée de Hold My Notes (sans lien avec ses auteurs).

- **Le deck** : toutes les notes forment une pile sur un bord de l'écran (droit, gauche ou bas). Au repos, de fines languettes ; au survol, les notes s'éventaillent, un onglet par note avec son titre vertical.
- **Notes flottantes** : titre, emoji, cinq couleurs pastel plus les vôtres, police par note, épinglage, Markdown mis en forme en direct (gras, italique, souligné, barré, titres, listes, cases à cocher, liens, tableaux).
- **Archive et recherche**, sélection multiple, suppression avec annulation pendant 10 s.
- **Export / import** : Markdown ou texte brut (un fichier par note), fichier unique, archive `.stickies` réimportable ; dossier Markdown facultatif (coffre Obsidian).
- **Chiffrement** AES-GCM, clé dans le Trousseau. Aucun compte, aucun serveur, aucune télémétrie.
- **Synchronisation** facultative entre Mac par un dossier (iCloud Drive par défaut).
- **Raccourcis globaux** modifiables, mise à jour automatique, quatre langues.

Compilation : `./build_app.sh` (installe dans `~/Applications/Applications Personnelles`). Tests : `swift test`, `mSTICK --selftest`.
