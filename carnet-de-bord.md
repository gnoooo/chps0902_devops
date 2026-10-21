# Carnet de bord

Cours 6 DevOps pour le HPC, M2 CHPS, séance en pédagogie inversée.

Date : 21 octobre 2026
Dépôt : TODO URL

## Mission 1 - Pipeline minimal

Objectif : faire compiler et tester un code MPI par une machine autre que la mienne.

### Ce qui a été fait

Code de test : `src/bcast.c`, un `MPI_Bcast` de huit entiers. Le rang 0 envoie, les autres vérifient. Le programme retourne 1 si une valeur est fausse.

Build avec CMake et `find_package(MPI)`. Le test est déclaré dans CTest et lance `mpirun -np 4`.

Pipeline GitHub Actions dans `.github/workflows/ci.yml`. Deux jobs. Le job `build` compile dans l'image `gcc:13-bookworm`. Le job `test` récupère le dossier `build` par `needs` et artefacts, puis lance `ctest` et un `mpirun -np 4` direct.

### Preuves

Build et test en local :

```
$ cmake -B build -DCMAKE_BUILD_TYPE=Release
$ cmake --build build -j
$ ctest --test-dir build --output-on-failure
1/1 Test #1: bcast_np4 ........................   Passed    1.76 sec
100% tests passed out of 1
```

Pipeline : TODO URL du run

### Erreurs et résolutions

TODO

### Réponses aux questions de cadrage

Pourquoi le pipeline s'arrête-t-il si deux jobs d'un même stage échouent ?

TODO

Quelle différence entre un `mpirun` dans le conteneur CI et une exécution sur un cluster ?

TODO

Pourquoi le job de test échoue-t-il si `needs` est oublié alors que le build a réussi ?

TODO

### Bilan

TODO

## Mission 2 - Déclencheurs, règles et secrets

### Ce qui a été fait

TODO

### Preuves

TODO

### Erreurs et résolutions

TODO

### Réponses aux questions de cadrage

`rules` contre `only` et `except`, lequel écrire aujourd'hui et où retrouver l'autre ?

TODO

Que devient une variable protégée si le pipeline part d'une branche non protégée, et quel risque cela couvre-t-il ?

TODO

Pourquoi ne jamais écrire un secret dans le fichier de CI, même temporairement ?

TODO

### Bilan

TODO

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

Le cours utilise GitLab CI. Ce dépôt utilise GitHub Actions. Correspondance des notions employées ici.

TODO tableau en prose, une ligne par notion

## Auto-diagnostic

Acquis :

TODO

Points à retravailler :

TODO

Usage dans mes activités CHPS :

TODO
