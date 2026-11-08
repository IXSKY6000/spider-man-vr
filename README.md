# Webs / Liberty VR — Liberty City sur Quest 3

Prototype Godot **4.6.3**, GDScript, OpenXR et rendu Compatibility / OpenGL ES 3.
**La vraie carte fournie est maintenant intégrée**, avec les textures d'origine,
le terrain adouci sur des surfaces sélectionnées, l'océan et les déplacements.
Les toiles, le balancement, l'escalade et les missions ne sont pas encore implémentés.

La carte provient de **Quake332**, [Grand Theft Auto 3 — Liberty City](https://www.deviantart.com/quake332/art/Grand-Theft-Auto-3-Liberty-City-928693536).
Le RAR transmis par le lien Drive a pu être téléchargé et extrait. Les sources
OBJ, MTL et textures sont conservées sans modification dans `assets/maps/source/`.

## Résultat de l'import

- 1 170 015 triangles, découpés en **129 zones de 128 m** pour permettre le culling.
- Les matériaux sont regroupés en **trois atlas de 4096²**, avec déduplication des
  images identiques et conservation des résolutions originales (32 à 256 pixels).
- Le shader `city_atlas.gdshader` conserve les UV répétées des routes et façades,
  ainsi que la transparence découpée des arbres et grillages. Des marges répétées
  et des gradients de texture limités réduisent les débordements entre les atlas.
- Lissage de **4 080 sommets**, sur **52 616 triangles** de terre et d'herbe
  identifiés visuellement (matériaux source 138, 224, 226, 236 et 1559).
  Les bords, ruptures marquées et coordonnées horizontales sont préservés par
  le lissage ; les surfaces des bâtiments ne sont pas sélectionnées.
- Les normales et UV des autres surfaces sont conservées. L'éclairage ajoute
  soleil, ombres proches, ciel et brume légère. Les textures restent celles du
  modèle original ; cette étape ne crée pas de textures HD ni de nouveaux bâtiments.
- Les collisions sont créées autour du joueur, quatre zones au départ puis une
  zone par image dans un rayon de 240 m. Elles sont libérées au-delà de 400 m.
  Le modèle visuel reste chargé en mémoire ; il ne s'agit pas encore d'un
  streaming des fichiers depuis le disque.

Le rapport est dans `assets/maps/liberty_city.report.json`. Le point de départ
`[-105, 1, -465]` se trouve sur une rue dont le sol mesuré est à environ -0,05 m.
Le niveau initial de l'eau est **-15 m**, ajustable dans la configuration.

## Lancer le projet

Ouvrir `project.godot` dans Godot **4.6.3**, laisser l'import se terminer, puis F5.
L'import initial de la ville est plus long que celui de la petite zone de test.
Sur la machine cloud :

```sh
tools/godot.sh --xr-mode off
```

Le wrapper place les caches dans `/workspace/.runtime/godot`. Hors du cloud,
l'éditeur suffit. Pour PC VR, démarrer le runtime OpenXR puis lancer sans
`--xr-mode off`. Sans runtime XR actif, le mode clavier/souris prend le relais.

| Commande | Quest / Touch | PC |
| --- | --- | --- |
| Marcher selon le regard | Stick gauche | ZQSD / WASD / flèches |
| Courir | Clic du stick gauche | Maj |
| Tourner | Stick droit, crans de 30° | Clic puis souris |
| Sauter | A | Espace |
| Retour au départ | B | R |
| Libérer la souris | — | Échap |

La capsule suit horizontalement le casque et s'adapte à l'accroupissement.
Les rotations gardent la position de la tête. Une chute sous l'eau renvoie
au départ. Les contrôleurs sont représentés par de simples volumes rouges.
Le déplacement physique à travers un mur n'est pas encore masqué par un fondu.

`config/map.json` règle la scène, son placement, le point de départ, le niveau
et la taille de l'océan, le vent, la rugosité, le brouillard et les distances
visuelles. `stream_city=true` active le shader d'atlas et la physique par zones.
Si le GLB manque, une petite zone de test explicitement indiquée prend le relais.

## Eau

Le shader PBR diélectrique `shaders/water.gdshader` vise une eau de port calme :
Fresnel correspondant à un indice de réfraction de 1,333, reflets du ciel, éclats
du soleil, trois houles et rides irrégulières. Les détails sous-pixel s'atténuent
à distance pour réduire le scintillement en VR.

Une surface détaillée de 192 m suit la caméra sur une grille de 2 m. Ses vagues
s'aplatissent aux bords pour rejoindre quatre tuiles lointaines sans trou ni
superposition : environ 18 440 triangles et cinq appels de dessin pour l'océan.
La phase des vagues utilise les coordonnées du monde. La texture de normales
256² est générée par `assets/water/ripples.tres`, sans ressource externe.

Le rendu fonctionne en GLES3/OpenXR sans lecture des textures d'écran ou de
profondeur ni caméra de réflexion supplémentaire. Il reste opaque, sans écume
de rivage, réfraction, reflets des bâtiments ou flottabilité. `water_wind`
accepte 0 à 2, `water_roughness` règle la rugosité PBR.

## Reproduire la conversion

Le projet ZIP contient le GLB et les textures nécessaires pour jouer. Les
sources brutes et les caches ne sont pas dans ce ZIP. Pour refaire la conversion,
extraire le RAR dans `assets/maps/source/`, puis depuis la racine du projet :

```sh
blender --background --python-exit-code 1 --python tools/import_liberty_city.py -- \
  --source-dir 'assets/maps/source/Liberty City(GTA 3)'
tools/godot.sh --headless --xr-mode off --editor --import --quit
```

Le convertisseur corrige les chemins Windows du OBJ dans une copie dérivée,
crée les atlas, applique le lissage sélectionné et exporte `liberty_city.glb`.
`source/.gdignore` empêche Godot d'importer aussi les sources brutes.
Le fichier GLB volumineux est ignoré par Git et explicitement inclus par l'outil
de création du ZIP. Godot extrait ses atlas PNG à côté du GLB lors de l'import.
Le projet doit être livré avec son GLB ; un checkout Git sans cet asset revient
à la zone de test. Le script général `tools/prepare_map.py` reste disponible
pour d'autres scènes OBJ/FBX/GLB/glTF/BLEND/DAE.

## APK Quest 3

Le préréglage **Quest 3** utilise Gradle, Android ARM64, OpenXR et le paquet
`org.liberty.websvr`. Le plugin officiel
[Godot OpenXR Vendors 4.3.0](https://github.com/GodotVR/godot_openxr_vendors/releases/tag/4.3.0-stable)
est inclus avec ses licences ; l'option Meta active les déclarations VR Quest 3/3S.

Pour une nouvelle machine : modèles d'export **4.6.3**, JDK complet 17+ avec
`javac`, SDK Android Platform-Tools, Build-Tools **36.1.0**, Platform **36** et
NDK **29.0.14206865**. Configurer les chemins SDK/JDK dans l'éditeur et installer
le modèle de compilation Android depuis le menu Projet. `android/` est généré
et ignoré par Git. Ces dépendances sont déjà préparées dans `/workspace/.runtime`
sur cette machine cloud. Les téléchargements Godot/JDK/SDK ont été vérifiés avec
les sommes publiées par leurs fournisseurs.

```sh
tools/export_quest.sh
adb install -r build/webs-liberty-quest3.apk
```

Activer le mode développeur du Quest, autoriser le débogage USB et ouvrir l'app
via les sources inconnues. Le préréglage désactive le sondage ADB automatique
(`runnable=false`) sur le cloud ; l'activer sur une machine reliée au casque
permet le déploiement en un clic. L'APK utilise une signature de développement.

Le prototype n'a pas été exécuté sur un Quest physique. Le suivi des contrôleurs,
le confort, la mémoire et la cadence réelle restent à mesurer sur le casque.
La physique à 72 Hz n'est pas une mesure de performance graphique. Le modèle
reste détaillé : des LOD plus agressifs et des collisions simplifiées pourront
être nécessaires après cette mesure.

## Vérification et livraison

```sh
tools/test.sh
python3 tools/package_project.py
```

Les **19 contrôles du prototype** vérifient sol, marche, saut, gravité, mur,
rotation autour de la tête, retour sous l'eau, actions XR, import d'une fixture
GLB et couverture/recentrage de l'océan. Les **12 contrôles de la vraie ville**
vérifient chargement, remplacement de la zone de test, atlas, collisions proches,
altitude du départ, marche, saut, retour au sol et retour après chute.
Le script Blender de fixture vérifie également le lissage et le maintien des
bords et coordonnées horizontales. Les tests et leurs fixtures sont exclus de l'APK.

Le rendu OpenGL a été lancé et inspecté avec des captures de rue et une vue
d'ensemble. La signature de l'APK est vérifiée après l'export. Ces contrôles
ne remplacent pas un essai sur casque physique.

Livrables : `build/webs-liberty-quest3.apk`, `build/webs-liberty-godot.zip`,
`build/liberty-city-street.png` et `build/liberty-city-overview.png`.
