# MA3 Tools pour REAPER

Extension REAPER qui envoie des commandes OSC à une **grandMA3** pendant la lecture du projet, pour la passe d'enregistrement du timecode :

- **Pistes d'extras** (kick, snare, flams, hihat…) : chaque note MIDI d'un item envoie la commande de sa piste, par exemple `Go+ Sequence 12`. On peut aussi envoyer une commande à la fin de la note, par exemple pour relâcher un Flash. Le MIDI de la piste continue de partir normalement : on peut envoyer les deux.
- **Cuelist principale (marqueurs)** : au passage de chaque marqueur, envoi de `Goto Sequence 1 Cue N`. Une action nomme aussi les cues de la séquence avec les noms des marqueurs.

L'envoi suit l'audio : chaque message part au bon moment, bloc audio par bloc audio, et non par un script qui vérifierait la position de temps en temps.

## Installation

1. Récupérez le fichier de la dernière compilation : onglet **Actions** du dépôt, workflow « reaper », dernier build réussi, puis l'artefact `reaper_ma3tools-macos` (ou `-windows`).
2. Copiez `reaper_ma3tools.dylib` dans le dossier `UserPlugins` de REAPER. Pour le trouver : Options > Show REAPER resource path.
3. Sur Mac, le fichier n'est pas signé. Si macOS le bloque, lancez une fois dans le Terminal :
   `xattr -d com.apple.quarantine ~/Library/Application\ Support/REAPER/UserPlugins/reaper_ma3tools.dylib`
4. Relancez REAPER. Les actions « MA3 Tools : … » apparaissent dans la liste des actions (Actions > Show action list).

Testé en compilation sur Linux, macOS et Windows, et avec un faux REAPER (voir Tests). **Pas encore testé dans REAPER ni avec une vraie console.**

## Réglages sur la grandMA3

Dans le menu OSC de la console : ajoutez une ligne avec le port choisi (par exemple 8000), activez l'entrée (**Enable Input**) et la réception des commandes. D'après le manuel grandMA3, une commande texte reçue sur l'adresse `/cmd` est exécutée comme si on la tapait. Si vous mettez un préfixe côté console, indiquez le même dans MA3 Tools : l'adresse devient `/<préfixe>/cmd`.

## Utilisation

| Action | Rôle |
|---|---|
| MA3 Tools : réglages de la console | IP et port OSC de la console, préfixe, décalage en ms, envoi actif ou non |
| MA3 Tools : activer/désactiver l'envoi | Bouton on/off, à mettre dans une barre d'outils |
| MA3 Tools : régler le déclenchement des pistes sélectionnées | Menu : Séquence, Executor ou Macro, puis l'action, puis le numéro (voir ci-dessous) |
| MA3 Tools : commande libre des pistes sélectionnées | Commande de début de note et, en option, de fin de note, écrites à la main |
| MA3 Tools : réglages de la cuelist principale | Go à chaque marqueur, numéro de séquence, première cue, commandes |
| MA3 Tools : nommer les cues avec les noms des marqueurs | Envoie `Label Sequence 1 Cue N "nom"` pour chaque marqueur, après confirmation |
| MA3 Tools : envoyer une commande de test | Pour vérifier la liaison |
| MA3 Tools : afficher le résumé | Liste dans la console REAPER les pistes configurées et le nombre de messages |

### Menu de déclenchement
Sélectionnez une ou plusieurs pistes d'extras, puis lancez « régler le déclenchement ». Vous pouvez aussi mettre cette action dans le menu clic droit des pistes (Options > Customize menus/toolbars).

| Cible | Choix | Ce qui est envoyé (début / fin de note) |
|---|---|---|
| Séquence N | Go+ | `Go+ Sequence N` |
| | Goto la cue du numéro de page | `Goto Sequence N Cue {page}` (le nombre dans « page 3 ») |
| | Flash pendant la note | `/13.13.1.6.N` `Flash 1` / `Flash 0` |
| | Temp pendant la note | `/13.13.1.6.N` `Temp 1` / `Temp 0` |
| | On pendant la note, puis Off | `On Sequence N` / `Off Sequence N` |
| | Toggle, Top | `Toggle Sequence N`, `Top Sequence N` |
| Executor P.E | Bouton appuyé pendant la note | `/PageP/KeyE 1` / `/PageP/KeyE 0` : le bouton fait ce qui lui est assigné sur la console |
| | Go+ | `Go+ Page P.E` |
| | Fader à 100 % pendant la note | `FaderMaster Page P.E At 100` / `At 0` |
| | Fader à la vélocité | `FaderMaster Page P.E At {velpct}` / `At 0` |
| Macro N | Go+ | `Go+ Macro N` |

Sources : manuel grandMA3, pages « Remote Inputs > OSC » et « OSC Open Stage Control ». À vérifier sur votre version :
- `/13.13.1.6.N` est l'adresse des séquences dans le datapool 1. Sur la console, `Printf(ObjectList('Sequence 1')[1]:Addr())` donne l'adresse exacte.
- `/PageP/KeyE` attend 1 pour appuyer et 0 pour relâcher.

### Écrire une commande
- **Texte simple** : une ligne de commande grandMA3, envoyée sur `/cmd`. Exemples : `Go+ Sequence 12`, `Flash On Sequence 12`.
- **Message OSC brut** : commencez par `/`, puis les arguments séparés par des espaces. Les nombres deviennent des entiers ou des flottants, et le texte entre guillemets reste un seul argument. Exemple : `/13.13.1.6.12 Flash 1`.
- **Variables** :
  - pistes : `{note}`, `{vel}`, `{velpct}` (vélocité en %), `{chan}`, `{item}` (nom de l'item), `{page}` (le nombre dans « page N »), `{track}` ;
  - marqueurs : `{seq}`, `{cue}`, `{n}`, `{name}`, `{qname}` (le nom entre guillemets).

  Exemple : `Go+ Sequence 12 Cue {page}`.

### Notes
- Les items et les notes MIDI muets sont ignorés. Le mute de la piste ne coupe pas l'OSC : pour ne garder que l'OSC, retirez la sortie MIDI de la piste.
- Les items en boucle sont pris en compte.
- Sous Windows, les accents des menus peuvent mal s'afficher.
- Le décalage (ms) avance ou retarde tous les messages. La latence de sortie audio est déjà compensée, pour que les messages arrivent en même temps que le timecode.
- « Nommer les cues » ne crée pas les cues : elles doivent déjà exister dans la séquence. Le manuel grandMA3 ne décrit pas de façon de créer une cue vide en ligne de commande. À vérifier sur grandMA3 onPC.

## Compilation

Depuis le dossier `reaper/` :

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

CMake télécharge le SDK REAPER et WDL (Cockos) à des versions figées. Sur Mac, ajoutez `-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"` pour une version universelle.

## Tests
- `ma3tests` : encodage OSC, variables, logique d'envoi pendant la lecture (retours en arrière, sauts).
- `e2e` : charge l'extension compilée dans un faux REAPER, joue un petit projet en temps réel (marqueurs, notes, item en boucle, retour en arrière), et vérifie les messages UDP reçus ainsi que leur timing (écart attendu 250 ms, mesuré à ±20 ms près).
