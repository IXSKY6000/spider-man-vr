# Webs / Liberty VR — 0.2, rendu net et éclairage précalculé

Prototype Godot **4.6.3**, GDScript, OpenXR et rendu Compatibility / OpenGL ES 3.
**La vraie carte fournie est maintenant intégrée**, avec les textures d'origine,
le terrain adouci sur des surfaces sélectionnées, l'océan et les déplacements.
Les toiles, le balancement, l'escalade et les missions ne sont pas encore implémentés.

[Aperçu des ombres dans la rue](docs/previews/street.png) ·
[Aperçu du parc](docs/previews/park.png) ·
[Soleil visible dans le ciel](docs/previews/sky.png)

La carte provient de **Quake332**, [Grand Theft Auto 3 — Liberty City](https://www.deviantart.com/quake332/art/Grand-Theft-Auto-3-Liberty-City-928693536).
Le RAR transmis par le lien Drive a pu être téléchargé et extrait. Les sources
OBJ, MTL et textures sont conservées sans modification dans `assets/maps/source/`.

## Netteté dans le casque

Le rendu OpenXR est réglé à **115 % de la taille recommandée par le runtime, par
dimension**, soit environ 32 % de pixels supplémentaires. Le bouton **Y du
contrôleur gauche** alterne entre 115 %, 130 % et 100 % ; le niveau apparaît sur
l'affichage au poignet. Le réglage à 100 % permet de privilégier la fluidité.
Le nombre exact de pixels par œil dépend du runtime et est écrit dans le journal
`XR_RENDER_SCALE ... target=...`.

La réduction automatique de résolution Meta est désactivée, l'anticrénelage est
passé à **MSAA 4×** et le filtrage anisotrope à **16×**. La fenêtre PC est en
1920×1080 ; cette taille de fenêtre ne détermine pas celle des yeux OpenXR.
`xr_render_scale` permet de modifier le niveau initial. Ces changements ciblent
l'image globale dans le casque, conformément au problème signalé ; les textures
d'origine sont conservées à leur résolution native.

## Soleil de journée et ombres fixes

Un soleil est placé à **68° au-dessus de l’horizon**, avec un azimut de −35°.
Le ciel procédural bleu contient un disque solaire visible et un halo discret.
Le ciel, la lumière directionnelle qui éclaire l’eau et les ombres de la ville
partagent exactement la même direction. Le brouillard lointain laisse le soleil
visible. Changer la direction du soleil nécessite de recalculer les ombres.

Les ombres des bâtiments, ponts et arbres sont précalculées dans **quatre images
solaires de 4096²**, couvrant 1 956 m dans le plan du soleil, soit environ **24 cm
par texel**. Elles enregistrent la profondeur depuis le soleil en RGB24, sans
compression destructive, mipmaps ni conversion sRGB. Les feuilles transparentes
sont découpées pendant le calcul. À l’exécution, le shader compare la position
des surfaces à ces images fixes : aucun passage de rendu d’ombres n’est effectué
par image. Quatre comparaisons pondérées adoucissent les contours, avec une
correction suivant le plan de la surface pour éviter les stries d’auto-ombrage.

Cette projection donne des silhouettes d’ombres continues entre les triangles,
indépendantes des UV des façades et du terrain. C’est une carte d’ombre solaire
figée, **pas une lightmap d’illumination globale** : l’éclairage ambiant est
approximé par une teinte du ciel et du sol. Les anciennes lightmaps par zones
ont été retirées. Aucun ray marching ou ray tracing n’est exécuté dans le casque.
Les objets mobiles ne modifient pas ces ombres fixes. `lighting_exposure` règle
la luminosité de la ville.

## Résultat de l'import

- 1 170 015 triangles, découpés en **129 zones de 128 m** pour permettre le culling.
- Les matériaux sont regroupés en **trois atlas de 4096²**, avec déduplication des
  images identiques et conservation des résolutions originales (32 à 256 pixels).
- Le shader `city_atlas.gdshader` conserve les UV répétées des routes et façades,
  ainsi que la transparence découpée des arbres et grillages. Un filtrage
  anisotrope manuel à quatre prises et des mipmaps limitées empêchent les
  débordements entre les images de l’atlas.
- Lissage de **4 080 sommets**, sur **52 616 triangles** de terre et d'herbe
  identifiés visuellement (matériaux source 138, 224, 226, 236 et 1559).
  Les bords, ruptures marquées et coordonnées horizontales sont préservés par
  le lissage ; les surfaces des bâtiments ne sont pas sélectionnées.
- Les UV de couleur sont conservées ; les métadonnées des atlas sont encodées
  dans les couleurs de sommets. Les ombres n’utilisent pas le dépliage UV2.
  Les textures restent celles du modèle original ; cette étape ne crée pas
  de textures HD ni de nouveaux bâtiments.
- Les collisions sont créées autour du joueur, quatre zones au départ puis une
  zone par image dans un rayon de 240 m. Elles sont libérées au-delà de 400 m.
  Les faces physiques sont actives des deux côtés, y compris sur les ponts.
  Le modèle visuel reste chargé en mémoire ; il ne s'agit pas encore d'un
  streaming des fichiers depuis le disque.
- Les LOD de maillage sont générés à l'import Godot et sélectionnés avec un seuil
  d'erreur de **0,75 pixel** (`lod_pixel_error`). La disparition lointaine est
  progressive sur 140 m avec l'alpha hashing natif, plutôt qu'une coupure nette.

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
| Niveau de netteté | Y, main gauche | `xr_render_scale` dans la configuration |
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

**L'ancienne eau a aussi été remplacée sur 290 triangles dans 11 groupes de
bassins/piscines.** Les matériaux aquatiques source 255, 1098, 1148 et 1169 ont
été identifiés visuellement ; leurs faces horizontales utilisent maintenant le
nouveau shader à leur altitude d'origine. Les parois ne sont pas supprimées.
Ces petites surfaces ont des rides calmes, sans déplacement géométrique, pour
préserver leur contour. Elles sont exclues des collisions et du bake statique.

## Reproduire la conversion

Le projet ZIP contient le GLB et les textures nécessaires pour jouer. Les
sources brutes et les caches ne sont pas dans ce ZIP. Pour refaire la conversion,
extraire le RAR dans `assets/maps/source/`, puis depuis la racine du projet :

```sh
blender --background --python-exit-code 1 --python tools/import_liberty_city.py -- \
  --source-dir 'assets/maps/source/Liberty City(GTA 3)'
tools/godot.sh --headless --xr-mode off --editor --import --quit
# Avec un affichage OpenGL actif (DISPLAY=:99 dans le cloud) :
tools/godot.sh --xr-mode off --audio-driver Dummy --script tools/bake_sun_shadows.gd
tools/godot.sh --headless --xr-mode off --editor --import --quit
```

Le convertisseur corrige les chemins Windows du OBJ dans une copie dérivée,
crée les atlas, applique le lissage sélectionné et exporte `liberty_city.glb`.
Le script de calcul solaire charge la géométrie complète, sans LOD, exclut
l’eau et écrit `assets/shadows/sun.json` et les quatre images. Il faut un vrai
contexte graphique OpenGL ; le mode `--headless` ne rend pas ces images.
L’option `-- --pilot` produit une petite zone de contrôle près du départ.
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

Les **22 contrôles du prototype** vérifient sol, marche, saut, gravité, mur,
rotation autour de la tête, retour sous l'eau, actions XR, import d'une fixture
GLB, couverture/recentrage de l'océan et le réglage de netteté. Les contrôles de la vraie ville
vérifient chargement, remplacement de la zone de test, atlas, collisions proches,
altitude du départ, marche, saut, retour au sol et retour après chute.
Les contrôles de la ville vérifient aussi les cartes solaires, l’alignement du
soleil avec le ciel et les ombres, les indices LOD réellement fournis au moteur,
le réglage XR et la nouvelle eau sans collision. Deux rayons physiques
indépendants vérifient aussi les profondeurs précalculées du pont et d’une rue
éclairée, avec une tolérance de 1 cm.
Le script Blender de fixture vérifie également le lissage et le maintien des
bords et coordonnées horizontales. Les tests et leurs fixtures sont exclus de l'APK.

Le rendu OpenGL a été lancé et inspecté avec des captures de rue et une vue
d'ensemble. La signature de l'APK est vérifiée après l'export. Ces contrôles
ne remplacent pas un essai sur casque physique.

Livrables : `build/webs-liberty-quest3.apk`, `build/webs-liberty-godot.zip`,
`build/sun-street-full.png`, `build/sun-park-full.png` et `build/sun-sky-full.png`.
