# mSTICK

[English](README.md)

Notes de bureau empilables, chiffrées et toujours à portée de main. Version personnelle inspirée de Hold My Notes (sans lien avec ses auteurs).

- **Des notes qui sont de vraies fenêtres** sur le bureau : sombres par défaut (ou claires, ou celles du système), titre centré, huit croix de fermeture (à gauche ou à droite), une couleur par note plus les vôtres, flotter dessus, coller au bureau, tous les bureaux. Markdown mis en forme en direct.
- **Piles** : déposez une note sur une autre, elles s'empilent en un seul bloc déplaçable ; un clic sur une barre ouvre la note ; couleurs en spectre, uniques ou identiques.
- **Fan** (⌥F) : feuilletez vos notes comme un jeu de cartes (flèches ou glissement du pavé), ⏎ pour ouvrir, taper pour écrire une nouvelle note. **Peek** (⌥`) : une touche sort la dernière note au-dessus de toute appli, une seconde la range.
- **Smart Calc** : `price = $129`, `discount = 27%`, `sale price = price - discount` affiche `→ $94.17` à côté de la ligne ; `567+45 =` reçoit son résultat au retour chariot.
- **Commandes « / »** : liste à cocher, tableau, séparateur, date, rappel, flotter, coller, couleur…
- **Rappels** en langage naturel (français, anglais, espagnol, italien) : `rappelle-moi demain à 20h de acheter du pain`, puis Retour. La note s'ouvre à l'heure dite.
- **Bibliothèque et archive** : recherche,, sélection multiple, suppression avec annulation pendant 10 s.
- **Export / import** : Markdown ou texte brut (un fichier par note), fichier unique, archive `.stickies` réimportable ; dossier Markdown facultatif (coffre Obsidian).
- **Chiffrement** AES-GCM, clé dans le Trousseau. Aucun compte, aucun serveur, aucune télémétrie.
- **Synchronisation** facultative entre Mac par un dossier (iCloud Drive par défaut).
- **Raccourcis globaux** modifiables (nouvelle note ⌥⌘N, Fan ⌥F, Peek ⌥`, Bibliothèque ⌥⌘L), mise à jour automatique, quatre langues.

Compilation : `./build_app.sh` (installe dans `~/Applications/Applications Personnelles`). Tests : `swift test`, `mSTICK --selftest`.
