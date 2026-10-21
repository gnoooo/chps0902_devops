# Carnet de bord

Cours 6 DevOps pour le HPC, M2 CHPS, séance en pédagogie inversée.

Date : 21 octobre 2026
Dépôt : https://github.com/gnoooo/chps0902_visualization_devops

## Mission 1 - Pipeline minimal

Objectif : faire compiler et tester un code MPI par une machine autre que la mienne.

### Ce qui a été fait

Le code de test est `src/bcast.c`. Le rang 0 envoie huit entiers par `MPI_Bcast`, les autres vérifient les valeurs reçues. Le programme retourne 1 si une valeur est fausse, ce qui suffit à faire échouer le test.

Le build passe par CMake et `find_package(MPI)`. Le test est déclaré dans CTest et lance `mpirun -np 4` sur le binaire.

Le pipeline est dans `.github/workflows/ci.yml`. Il contient deux jobs. Le job `build` compile dans l'image `gcc:13-bookworm` et publie le dossier `build` en artefact. Le job `test` déclare `needs: build`, télécharge l'artefact, puis lance `ctest` et un `mpirun -np 4` direct.

Le choix de l'image suit le cours. Le conteneur impose deux options à `mpirun`. On y est root, d'où `--allow-run-as-root`. Le runner n'a que quelques coeurs, d'où `--oversubscribe` pour caser quatre rangs.

### Preuves

En local, avant tout pipeline :

```
$ cmake -B build -DCMAKE_BUILD_TYPE=Release
$ cmake --build build -j
$ ctest --test-dir build --output-on-failure
1/1 Test #1: bcast_np4 ........................   Passed    1.76 sec
100% tests passed, 0 tests failed out of 1
```

Dans le job `test` du run 39573283731 :

```
1/1 Test #1: bcast_np4 ........................   Passed    0.33 sec
100% tests passed, 0 tests failed out of 1
MPI_Bcast OK sur 4 rangs
```

Les quatre rangs tournent donc bien dans le conteneur du runner.

### Erreurs et résolutions

Première erreur, l'installation des dépendances échoue. `apt-get install cmake libopenmpi-dev` casse sur `gfortran` avec le message `update-alternatives: error: alternative path /usr/bin/gfortran doesn't exist`. Le paquet arrive par une recommandation de `libopenmpi-dev` et l'image `gcc:13-bookworm` n'a pas le binaire attendu. Résolution, ajouter `--no-install-recommends`, ce qui évite d'installer Fortran dont nous n'avons pas besoin.

Deuxième erreur, `ctest` échoue dans le job `test` alors que le build est vert. Le message est `mpiexec was unable to launch the specified application as it could not access or execute an executable`. L'artefact est bien là mais il a perdu son bit exécutable, car `upload-artifact` ne conserve pas les permissions. Résolution, un `chmod +x build/bcast` après le téléchargement.

### Réponses aux questions de cadrage

Que se passe-t-il si deux jobs d'un même stage échouent, et pourquoi ce comportement est-il souhaitable ?

Dans GitLab, un stage est une barrière. Les jobs d'un même stage démarrent ensemble et le stage suivant ne part que si tous ont réussi. Si deux jobs du stage build échouent, le pipeline s'arrête et le stage test n'est jamais lancé. C'est souhaitable pour deux raisons. On ne teste pas un binaire qui n'a pas pu être produit, et on ne consomme pas de runners pour un résultat déjà invalide.

GitHub Actions ne connaît pas les stages. Le seul ordre est celui du graphe `needs`. Sans `needs`, tous les jobs démarrent en même temps, ce que l'expérience de la question suivante montre bien.

Quelle différence entre un `mpirun` dans le conteneur CI et une exécution sur un cluster ?

Dans le conteneur, les quatre rangs sont des processus sur une seule machine, sans ordonnanceur, sans réservation et sans réseau rapide. `--oversubscribe` ment sur le nombre de coeurs disponibles. Sur un cluster, `sbatch` réserve des noeuds et un temps, `srun` place les rangs sur des machines distinctes, MPI passe par l'interconnexion, et les modules fixent l'environnement. Le test CI prouve que le code compile et que la logique MPI est correcte. Il ne prouve ni la mise à l'échelle, ni le comportement réseau, ni la reproductibilité de l'environnement. C'est le sens de CI différent de l'exécution cluster.

Pourquoi le job de test échoue-t-il si `needs` est oublié alors que le build a réussi ?

Sans `needs`, les deux jobs démarrent en même temps. Le job `test` peut donc arriver à l'étape de téléchargement avant que le job `build` ait publié son artefact. `download-artifact` échoue alors avec `Unable to find any artifacts for the associated workflow`.

L'expérience l'a confirmé à moitié, et c'est instructif. Sur le run 39574168499, build et test ont démarré à 09:04:53. Le build a publié à 09:05:21 et le téléchargement a eu lieu à 09:05:24. Le test est passé, mais par chance, parce que l'initialisation du conteneur a retardé le téléchargement de trente secondes. Sans ce délai, le téléchargement serait arrivé avant la publication et le job aurait échoué. Le problème n'est donc pas une règle mais une course. `needs` supprime la course, rend la dépendance explicite et permet aussi de ne pas lancer le test quand le build échoue.

### Bilan

Ce qui fonctionne, le pipeline compile et les quatre rangs communiquent dans le conteneur.

Ce qui ne fonctionne pas encore, rien de bloquant, mais le test reste mono-noeud et ne dit rien de la mise à l'échelle.

Ce que je referais autrement, poser `needs` dès le premier jet et tester les permissions d'artefact avant de chercher ailleurs.

## Mission 2 - Déclencheurs, règles et secrets

### Ce qui a été fait

Un job `lint` lance `cppcheck --enable=warning,style --error-exitcode=1 src/`. Il porte la condition `if: github.event_name == 'pull_request'`, donc il ne tourne que sur une pull request.

Un job `package` crée `bcast-<tag>.tar.gz`, calcule son empreinte avec `sha256sum` et publie les deux fichiers en artefact. Il porte la condition `if: startsWith(github.ref, 'refs/tags/v')` et déclare `needs: build`.

Un job `secret_demo` ne tourne que sur `workflow_dispatch`. Il lit le secret `FAKE_REGISTRY_TOKEN` et le passe à `docker login` par `--password-stdin`, vers un registre qui n'existe pas. L'échec du login est attendu, le but est de voir si la valeur fuit dans les logs.

Le déclencheur de la pull request a été testé sur une vraie PR, la numéro 1, avec une petite modification du code. Le tag `v0.1.0` a été créé sur `main` pour déclencher le packaging.

### Preuves

Sur la pull request 1, le job lint tourne et passe :

```
lint success
build success
test success
package skipped
```

Sur le push du tag `v0.1.0`, seul le package est ajouté :

```
build success
test success
package success
lint skipped
```

Le package produit une empreinte vérifiable :

```
af5e656487fd737efc14349ad5855463fdd0bc902e5a0f9e44aa42eb5c7e31c3  bcast-v0.1.0.tar.gz
```

Sur le run manuel 39573937102, le secret est masqué par la plateforme :

```
env:
  FAKE_REGISTRY_TOKEN: ***
Error response from daemon: Get "https://registry.invalid/v2/": no such host
secret present en variable, non affiche dans les logs
```

La valeur n'apparaît nulle part dans le journal du job.

### Erreurs et résolutions

Le login vers `registry.invalid` échoue, c'est voulu. La première version du job sortait en erreur et salissait le pipeline. Résolution, ajouter `|| true` et garder la preuve dans le log.

La pull request d'expérience sur `needs` a été fermée sans fusion, puis la branche a été supprimée pour ne pas laisser de code faux dans le dépôt.

### Réponses aux questions de cadrage

`rules` contre `only` et `except`, lequel écrire aujourd'hui, et où retrouver l'autre ?

On écrit `rules` dans GitLab. `only` et `except` sont dépréciés, ils ne servent plus que dans les dépôts anciens et la documentation historique. Dans ce dépôt GitHub, l'équivalent de `rules` est la combinaison de `on:` pour le déclencheur et de `if:` pour la condition, ce qui donne ici `if: github.event_name == 'pull_request'` et `if: startsWith(github.ref, 'refs/tags/v')`.

Que devient une variable protégée si le pipeline part d'une branche non protégée, et quel risque cela couvre-t-il ?

La variable n'est pas injectée, elle est vide dans le job. Le job échoue donc à l'étape qui l'utilise, ou tourne sans le secret. Le mécanisme couvre un risque précis. Une personne qui a le droit de pousser une branche peut modifier le fichier de CI et faire afficher la variable. En la réservant aux branches et tags protégés, on limite la fuite aux commits relus et approuvés. GitHub n'a pas cette notion, le plus proche est un environment avec des règles de protection. Je réponds donc ici par la documentation GitLab, sans expérience directe, et je le signale.

Pourquoi ne jamais écrire un secret dans le fichier de CI, même temporairement ?

Parce que l'historique Git est définitif. Le commit reste dans le dépôt, dans les clones et dans les forks, même après suppression de la ligne. Les journaux de job et les pull requests peuvent aussi l'exposer. Le corriger demande de réécrire l'historique et de révoquer le secret. Ici la valeur de démonstration est fausse, et elle est tout de même stockée dans les secrets du dépôt, pas dans le fichier.

### Bilan

Ce qui fonctionne, les trois déclencheurs se comportent comme prévu et le secret reste masqué.

Ce qui ne fonctionne pas, la notion de variable protégée n'existe pas sur GitHub, la réponse reste documentaire.

Ce que je referais autrement, écrire les conditions dans un seul fichier dès le départ plutôt que d'ajouter les jobs un par un.

## Mission 3 - Du CI vers Slurm

### Ce qui a été fait

TODO

### Preuves

TODO

### Erreurs et résolutions

TODO

### Réponses aux questions de cadrage

Pourquoi le job CI doit-il porter un timeout alors que le job Slurm a déjà son wall-time ?

TODO

Le job reste PENDING vingt minutes, que se passe-t-il côté CI et comment le rendre observable ?

TODO

Le nightly échoue à 2 h du matin, trois questions avant de relancer, et distinction entre échec de code et échec d'infrastructure.

TODO

### Bilan

TODO

## Mission 4 - Spack, l'environnement comme code

### Ce qui a été fait

TODO

### Preuves

TODO

### Erreurs et résolutions

TODO

### Réponses aux questions de cadrage

Syntaxe d'une spec complète, exemple de hdf5 compilé avec GCC, MPI activé, Fortran activé, C++ désactivé.

TODO

Pourquoi `spack.lock` suffit à reproduire l'environnement et pourquoi `spack.yaml` seul ne suffit pas ?

TODO

Quel intérêt du buildcache pour un pipeline qui installe l'environnement à chaque exécution ?

TODO

### Bilan

TODO

## Correspondance GitLab

Le cours décrit GitLab CI et ce dépôt utilise GitHub Actions. Voici les notions employées, avec leur équivalent.

Les stages deviennent des jobs reliés par `needs`, il n'y a pas de barrière de stage.

Les artefacts et `needs` gardent le même rôle, avec `actions/upload-artifact` et `actions/download-artifact`.

`rules` avec `merge_request_event` devient `on: pull_request` plus un `if` sur `github.event_name`.

`rules` avec une expression régulière de tag devient un filtre `on: push: tags` plus un `if` sur `startsWith(github.ref, 'refs/tags/v')`.

`only` et `except` n'ont pas d'équivalent, le filtrage se fait dans `on:` et dans `if:`.

Une variable masquée devient un secret, masqué automatiquement dans les journaux.

Une variable protégée n'a pas d'équivalent direct, le plus proche est un environment avec des règles de protection.

`retry: when: runner_system_failure` n'a pas d'équivalent, la relance se fait à la main depuis l'interface.

`schedule` devient `on: schedule` avec une expression cron.

## Auto-diagnostic

Acquis :

TODO

Points à retravailler :

TODO

Usage dans mes activités CHPS :

TODO
