# Carnet de bord

Cours 6 DevOps pour le HPC, M2 CHPS, séance en pédagogie inversée.

Date : 21 octobre 2026 \
Dépôt : https://github.com/gnoooo/chps0902_devops

## Mission 1 (pipeline minimal)

> Objectif : faire compiler et tester un code MPI par une machine autre que la mienne.

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

Dans le job `test` du run 39604040524 :

```
1/1 Test #1: bcast_np4 ........................   Passed    0.34 sec
100% tests passed, 0 tests failed out of 1
MPI_Bcast OK sur 4 rangs
```

Les quatre rangs tournent donc bien dans le conteneur du runner.

### Erreurs et résolutions

Première erreur, l'installation des dépendances échoue. `apt-get install cmake libopenmpi-dev` casse sur `gfortran` avec le message `update-alternatives: error: alternative path /usr/bin/gfortran doesn't exist`. Le paquet arrive par une recommandation de `libopenmpi-dev` et l'image `gcc:13-bookworm` n'a pas le binaire attendu. 

> Résolution, ajouter `--no-install-recommends`, ce qui évite d'installer Fortran dont nous n'avons pas besoin.

Deuxième erreur, `ctest` échoue dans le job `test` alors que le build est vert. Le message est `mpiexec was unable to launch the specified application as it could not access or execute an executable`. L'artefact est bien là mais il a perdu son bit exécutable, car `upload-artifact` ne conserve pas les permissions. 

> Résolution, un `chmod +x build/bcast` après le téléchargement.

### Réponses aux questions

**Que se passe-t-il si deux jobs d'un même stage échouent, et pourquoi ce comportement est-il souhaitable ?**

Dans GitLab, un stage est une barrière. Les jobs d'un même stage démarrent ensemble et le stage suivant ne part que si tous ont réussi. Si deux jobs du stage build échouent, le pipeline s'arrête et le stage test n'est jamais lancé. C'est souhaitable pour deux raisons : on ne teste pas un binaire qui n'a pas pu être produit, et on ne consomme pas de runners pour un résultat déjà invalide.

GitHub Actions ne connaît pas les stages. Le seul ordre est celui du graphe `needs`. Sans `needs`, tous les jobs démarrent en même temps, ce que l'expérience de la question suivante montre bien.

---

**Quelle différence entre un `mpirun` dans le conteneur CI et une exécution sur un cluster ?**

Dans le conteneur, les quatre rangs sont des processus sur une seule machine, sans ordonnanceur, sans réservation et sans réseau rapide. `--oversubscribe` ment sur le nombre de coeurs disponibles. Sur un cluster, `sbatch` réserve des noeuds et un temps, `srun` place les rangs sur des machines distinctes, MPI passe par l'interconnexion, et les modules fixent l'environnement. Le test CI prouve que le code compile et que la logique MPI est correcte. Il ne prouve ni la mise à l'échelle, ni le comportement réseau, ni la reproductibilité de l'environnement. C'est le sens de CI différent de l'exécution cluster.

---

**Pourquoi le job de test échoue-t-il si `needs` est oublié alors que le build a réussi ?**

Sans `needs`, les deux jobs démarrent en même temps. Le job `test` peut donc arriver à l'étape de téléchargement avant que le job `build` ait publié son artefact. `download-artifact` échoue alors avec `Unable to find any artifacts for the associated workflow`.

L'expérience l'a confirmé à moitié, et c'est instructif. Sur un run où `needs` était retiré, build et test ont démarré à 09:04:53. Le build a publié à 09:05:21 et le téléchargement a eu lieu à 09:05:24. Le test est passé, mais par chance, parce que l'initialisation du conteneur a retardé le téléchargement de trente secondes. Sans ce délai, le téléchargement serait arrivé avant la publication et le job aurait échoué. Le problème n'est donc pas une règle mais une course. `needs` supprime la course, rend la dépendance explicite et permet aussi de ne pas lancer le test quand le build échoue. Cette observation date de l'ancien dépôt, elle n'a pas été rejouée ici parce qu'une course ne se reproduit pas à la demande.



### Bilan

Ce qui fonctionne : le pipeline compile et les quatre rangs communiquent dans le conteneur.

Ce qui ne fonctionne pas encore : rien de bloquant, mais le test reste mono-noeud et ne dit rien de la mise à l'échelle.

Ce que je referais autrement : poser `needs` dès le premier jet et tester les permissions d'artefact avant de chercher ailleurs.

## Mission 2 (déclencheurs, règles et secrets)

### Ce qui a été fait

Un job `lint` lance `cppcheck --enable=warning,style --error-exitcode=1 src/`. Il a la condition `if: github.event_name == 'pull_request'`, donc il se lance que sur une pull request.

Un job `package` crée `bcast-<tag>.tar.gz`, calcule son empreinte avec `sha256sum` et publie les deux fichiers en artefact. Il a la condition `if: startsWith(github.ref, 'refs/tags/v')` et déclare `needs: build`, il se lance donc s'il y a un tag avec la typo `vX.Y.Z` (et a besoin de l'étape de `build` aussi).

Un job `secret_demo` ne tourne que sur `workflow_dispatch`. Il lit le secret `FAKE_REGISTRY_TOKEN` et le passe à `docker login` par `--password-stdin`, vers un registre qui n'existe pas. L'échec du login est attendu, le but est de voir si la valeur fuit dans les logs.

Le déclencheur de la pull request a été testé sur une vraie PR, la numéro 1, avec une petite modification du code. Le tag `v0.1.0` a été créé sur `main` pour déclencher le packaging.

### Preuves

Sur la pull request 1, le job lint tourne et passe :

```
lint success
build success
test success
test_hpc skipped
package skipped
```

Sur le push du tag `v0.1.0`, run 39592079121, seul le package est ajouté :

```
build success
test success
package success
lint skipped
```

Le package produit une empreinte vérifiable :

```
18db22c7643d4b122c6776c3dc89250638f9c1691998b35da3bfe5cd52843f30  bcast-v0.1.0.tar.gz
```

Sur le run manuel 39604281725, le secret est masqué par la plateforme :

```
env:
  FAKE_REGISTRY_TOKEN: ***
Error response from daemon: Get "https://registry.invalid/v2/": no such host
secret present en variable, non affiche dans les logs
```

La valeur n'apparaît nulle part dans le journal du job.

### Erreurs et résolutions

Le login vers `registry.invalid` échoue et c'est voulu. La première version du job sortait en erreur et salissait le pipeline. 

> Résolution, ajouter `|| true` et garder la preuve dans le log.

La pull request d'expérience sur `needs` a été fermée sans fusion, puis la branche a été supprimée pour ne pas laisser de code faux dans le dépôt.

### Réponses aux questions

**`rules` contre `only` et `except`, lequel écrire aujourd'hui, et où retrouver l'autre ?**

On écrit `rules` dans GitLab. `only` et `except` sont dépréciés, ils ne servent plus que dans les dépôts anciens et la documentation historique. Dans ce dépôt GitHub, l'équivalent de `rules` est la combinaison de `on:` pour le déclencheur et de `if:` pour la condition, ce qui donne ici `if: github.event_name == 'pull_request'` et `if: startsWith(github.ref, 'refs/tags/v')`.

---

**Que devient une variable protégée si le pipeline part d'une branche non protégée, et quel risque cela couvre-t-il ?**

La variable n'est pas injectée, elle est vide dans le job. Le job échoue donc à l'étape qui l'utilise, ou tourne sans le secret. Le mécanisme couvre un risque précis : une personne qui a le droit de pousser une branche peut modifier le fichier de CI et faire afficher la variable. En la réservant aux branches et tags protégés, on limite la fuite aux commits relus et approuvés. GitHub n'a pas cette notion, le plus proche est un environment avec des règles de protection. Je réponds donc ici par la documentation GitLab, sans expérience directe, et je le signale.

---

**Pourquoi ne jamais écrire un secret dans le fichier de CI, même temporairement ?**

Parce que l'historique Git est définitif. Le commit reste dans le dépôt, dans les clones et dans les forks, même après suppression de la ligne. Les journaux de job et les pull requests peuvent aussi l'exposer. Le corriger demande de réécrire l'historique et de révoquer le secret (possiblement de contacter le support si la clé reste dans un cache ou fichier invisible côté GitLab/GitHub). Ici la valeur de démonstration est fausse, et elle est tout de même stockée dans les secrets du dépôt, pas dans le fichier.

### Bilan

Ce qui fonctionne : les trois déclencheurs se comportent comme prévu et le secret reste masqué.

Ce qui ne fonctionne pas : la notion de variable protégée n'existe pas sur GitHub, la réponse reste documentaire.

Ce que je referais autrement : écrire les conditions dans un seul fichier dès le départ plutôt que d'ajouter les jobs un par un.

## Mission 3 (du CI vers Slurm)

### Ce qui a été fait

Le cluster du Cours 5 a été redéployé sur GCP avec le blueprint `hpc-slurm.yaml` du Cluster Toolkit. Il donne un noeud de login avec une IP publique, deux noeuds de calcul de la partition `debug`, et un `/home` partagé par Filestore.

Le pare-feu du réseau n'ouvre le port 22 qu'aux plages IAP de Google. Un runner hébergé par GitHub ne peut donc pas se connecter au login par SSH. J'ai installé un runner auto-hébergé sur le noeud de login, avec le label `hpc-login` et un service systemd.

Deux jobs utilisent ce runner. `test_hpc` compile sur le login, soumet `slurm/job_ci.sh` avec `sbatch --parsable`, puis interroge `sacct` toutes les trente secondes jusqu'à un état terminal. Il porte `timeout-minutes: 45` et publie `ci-*.out` avec `if: always()`. `test_hpc_wait` fait la même chose en une ligne avec `sbatch --wait` et ne tourne que sur `workflow_dispatch`, pour comparer les deux façons d'attendre.

Les deux jobs portent aussi la condition `if: vars.HPC_RUNNER == 'on'`, ajoutée après la destruction du cluster. La variable n'existe pas sur le dépôt, ils sortent donc en `skipped` et le run se termine proprement au lieu de rester en file sans runner. Recréer la variable sur un cluster redéployé suffit à les rallumer, le code des jobs n'a pas bougé.

Le script `slurm/job_ci.sh` porte les en-têtes SBATCH, charge Lmod, reconstruit la liste des noeuds avec `scontrol show hostnames`, puis lance `mpirun` sur cette liste.

Le cours demande d'expérimenter avec `retry: when: runner_system_failure`. GitLab ne relance que sur une panne du runner, jamais sur un échec du script, et cette limite est la bonne. GitHub n'a pas ce filtre, la relance d'un job repart quel que soit l'échec, donc je ne l'active pas et je relance à la main avec `gh run rerun --failed`.

Les deux échecs de la séance illustrent la règle : le premier run a échoué sur `apt-get`, un gfortran absent de l'image, une relance aurait redonné la même erreur. Le job 11 a échoué côté CI alors que Slurm l'avait accepté, un problème de synchronisation, une relance aurait été légitime. On relance l'infrastructure, jamais le code.

Pour l'attente, `sbatch --wait` convient quand on soumet à la main et qu'on regarde la file en même temps, le polling convient quand c'est la CI qui doit tenir le délai et expliquer l'attente.

Le build n'est pas réutilisé depuis le conteneur. Le binaire du conteneur Debian ne tourne pas sur Rocky Linux avec l'OpenMPI de Spack, il faut recompiler avec les modules du cluster.

### Preuves

Run 39582070775, job `test_hpc` :

```
job soumis 10
10:07:07 job 10 PENDING
10:07:37 job 10 RUNNING
10:08:07 job 10 RUNNING
10:08:37 job 10 COMPLETED
rang 0 recoit 0
MPI_Bcast OK sur 2 rangs
rang 1 recoit 0
SUCCESS: test MPI passe sur hpcslurm-debugnodeset-0 hpcslurm-debugnodeset-1
```

Run 39582567650, job `test_hpc_wait`, même commit, même script :

```
10:10:28 Submitted batch job 11
10:17:02 sbatch: error: Job 11 no longer found and exit code not found
```

Le job 11 était encore dans la file à ce moment. Il a tourné plus tard, et son fichier est arrivé après l'envoi de l'artefact :

```
$ sacct -j 11 -o JobID,Start,End,State,ExitCode
11  2026-10-21T10:22:51  2026-10-21T10:22:53  COMPLETED  0:0
```

L'artefact `hpc-logs-wait` n'a donc pas été produit, avec le message `No files were found with the provided path: ci-*.out`. Le job a réussi, la CI n'en a rien su.

### Erreurs et résolutions

Première erreur, `module load cmake` répond `unknown module` dans le job. Un shell non interactif ne lit pas `/etc/profile`, donc `MODULEPATH` ne contient pas les modules de Spack. 

> Résolution, déclarer `shell: bash -l {0}` sur les étapes, ce qui lance un shell de connexion.

Deuxième erreur, le job Slurm reste PENDING indéfiniment. `scontrol show job` donne `Reason=PartitionConfig`. Le job demandait quatre tâches, soit par défaut 29,5 Go de mémoire, alors que la partition entière n'a que deux coeurs, 15 Go de mémoire réelle et `Exclusive=NODE`. 

> Résolution, une tâche par noeud et `--mem=0`, ce qui laisse Slurm compter la mémoire du noeud entier.

Troisième erreur, la sortie du job est invisible depuis le login. `#SBATCH -o /tmp/...` écrit sur le disque local du noeud de calcul, pas sur le Filestore partagé. 

> Résolution, écrire dans le répertoire de soumission, qui est sur `/home`.

Quatrième erreur, plus intéressante, le job passe, mais affiche `MPI_Bcast OK sur 1 rangs`, et chaque rang croit être seul. `srun -n 2 ./hello` affiche deux fois `rang 0 sur 1`. `ompi_info` montre que l'OpenMPI de Spack est compilé `--without-slurm`. `srun` lance bien deux tâches, mais aucune ne reçoit son rang dans l'environnement PMIx, donc chaque processus démarre comme un monde MPI à un rang. La solution évidente serait `srun --mpi=pmix`, mais l'installation n'a pas le support Slurm. J'ai donc gardé `srun` pour l'allocation et lancé `mpirun --host` sur la liste des noeuds. Le test affiche maintenant deux rangs distincts, un par noeud.

### Réponses aux questions de cadrage

**Pourquoi le job CI doit-il porter un timeout alors que le job Slurm a déjà son wall-time ?**

Le wall-time est un contrat avec Slurm, il ne couvre que l'exécution, à partir du moment où le job démarre. Il ne couvre ni la file d'attente, ni le démarrage des noeuds, ni la soumission, ni la remontée des artefacts. Un job bloqué en PENDING ne consomme jamais son wall-time, il peut donc rester en file indéfiniment sans que Slurm ne le tue.

Le timeout de la CI couvre toute l'étape, attente comprise. Sans lui, le runner auto-hébergé reste occupé par un job qui n'avance plus (ce qui n'est pas bon). Ici il n'y a qu'un runner, donc un job bloqué bloque tout le dépôt, ce qui est arrivé pendant les essais. La valeur doit se lire comme attente maximale plus wall-time plus marge. Ici quarante-cinq minutes pour dix minutes de calcul.

---

**Le job reste PENDING vingt minutes, que se passe-t-il côté CI et comment le rendre observable ?**

La CI ne voit qu'une suite d'états identiques, et rien ne distingue une file lente d'un job oublié. Le runner reste occupé, les artefacts ne remontent pas, et le pipeline ne rend pas la main. Sans timeout, l'étape ne finit jamais.

Ce qui rend la chose observable, c'est d'écrire l'horodatage et la raison à chaque tour. J'ai ajouté `squeue -o %r`, qui affiche `PartitionConfig`, `Resources` ou `Priority`, et qui dit donc si la demande est impossible ou si elle attend son tour. J'ajoute aussi un timeout court pour la file, distinct de celui du calcul, et l'envoi du log en artefact systématique. Une file qui dépasse le seuil peut alors être annulée avec un message clair au lieu d'expirer sans explication.

---

**Le nightly échoue à 2 h du matin, trois questions avant de relancer, et distinction entre échec de code et échec d'infrastructure.**

Trois questions avant de relancer :
- Le job a-t-il démarré, ou est-il resté en file ? 
- Le même commit passe-t-il à la main ? 
- L'échec est-il reproductible, ou vu une seule fois ?

La distinction se fait sur deux sources. `sacct` donne l'état final. `NODE_FAIL`, `TIMEOUT`, `OUT_OF_MEMORY`, `CANCELLED` ou `PREEMPTED` désignent l'infrastructure. `FAILED` avec un code de sortie non nul désigne le code, ou l'environnement, car le programme a tourné et a rendu son verdict. Le journal du job complète, un échec à la compilation ou un module absent n'est pas un échec du calcul.

Ensuite, la réponse dépend du diagnostic. Un incident d'infrastructure se relance tel quel, sans toucher au code. Un échec de code se corrige avant de relancer, sinon on relance une erreur. Un test instable, qui passe deux fois sur trois, se relance mais se documente, sinon il use la confiance dans le pipeline. Dans les trois cas, je note l'heure, l'identifiant du run et l'identifiant du job Slurm, parce que sans eux l'incident est impossible à relire une semaine plus tard.

### Bilan

Ce qui fonctionne : la CI soumet un vrai job Slurm, suit son état et récupère sa sortie, sur un cluster privé qui n'est pas joignable depuis Internet.

Ce qui ne fonctionne pas : `sbatch --wait` ne rend pas la main correctement quand le job attend en file, il rend une erreur alors que le job est encore vivant. Le polling est plus verbeux mais plus honnête.

Ce que je referais autrement : vérifier la raison d'attente dès la première soumission, un `PartitionConfig` se voit en une minute et m'a coûté deux runs.

## Mission 4 (spack, l'environnement comme code)

### Ce qui a été fait

Le cluster fournit déjà Spack dans `/opt/apps/spack`, comme sur ROMEO, donc je ne clone pas le dépôt officiel. Je travaille dans un environnement dédié, le répertoire `spack/` du dépôt.

Le gcc 11.5.0 du système est déjà déclaré, `spack compiler find` répond `Found no new compilers`. Aucune compilation de compilateur. Les deux specs utilisent `%gcc`.

Le fichier `spack/spack.yaml` déclare deux racines, `openmpi@5.0.8%gcc` et `cmake@3.31.9%gcc`, sur la cible `x86_64_v3`, avec `unify: true`. Il déclare aussi un upstream, l'arbre d'installation du cluster, et un arbre d'installation dans le home, car `/opt/apps/spack` n'est pas écrivable.

`spack -D spack concretize -f` produit `spack/spack.lock`. Les deux fichiers sont commités.

`spack -D spack install` réutilise les paquets de l'upstream et ne compile rien. La vue de l'environnement fournit cmake et mpirun, le projet se configure, se compile et passe son test avec ces outils.

Le buildcache est ensuite fabriqué et consommé pour de vrai, sur le même noeud de login, dans un second environnement `~/bc-demo` volontairement sans upstream. Sans upstream les paquets se compilent, c'est la condition pour avoir un binaire à mettre en cache. Le script `spack/buildcache-demo.sh` du dépôt enchaîne les cinq étapes, concrétiser, installer depuis les sources, pousser le binaire dans un miroir local, désinstaller, réinstaller avec `--cache-only`. Le miroir est un simple répertoire, il pourrait être un bucket ou un dépôt OCI.

### Preuves

Vérification dans un clone neuf du dépôt, sur le noeud de login :

```
$ spack compiler find
==> Found no new compilers

$ spack -D spack concretize -f
==> Updating view at /tmp/spack-repo/spack/.spack-env/view

$ spack -D spack find
==> In environment /tmp/spack-repo/spack
==> 2 root specs
-- no arch / no compilers ---------------------------------------
[^] cmake@3.31.9
[^] openmpi@5.0.8

$ spack -D spack install | tail -1
[+] /opt/apps/spack/opt/spack/[padded-to-128-chars]/linux-x86_64_v3/openmpi-5.0.8-z7iplfroyys323rngc7fvppi73d5smcj
```

Le marqueur `[^]` dit que la spec vient de l'upstream et le `[+]` dit qu'elle est installée. Chaque paquet de l'environnement donne une ligne `[+]` dans ce genre, et aucune ligne de compilation.

```
$ export PATH=spack/.spack-env/view/bin:$PATH
$ mpirun --version | head -1
mpirun (Open MPI) 5.0.8
$ cmake -S . -B /tmp/b2 -DCMAKE_BUILD_TYPE=Release && cmake --build /tmp/b2 -j2
[100%] Built target bcast
$ mpirun --allow-run-as-root --oversubscribe -np 2 /tmp/b2/bcast
rang 0 recoit 0
rang 1 recoit 0
MPI_Bcast OK sur 2 rangs
```

Extrait de `spack/spack.lock`, la racine openmpi :

```
"z7iplfroyys323rngc7fvppi73d5smcj":{"name":"openmpi","version":"5.0.8",
 "arch":{"platform":"linux","platform_os":"rocky9","target":"x86_64_v3"},
 "parameters":{"fortran":true,"schedulers":["none"],...},
 "dependencies":[{"name":"prrte","hash":"y2cjdzyqbpyyyklpdhzod5oi5o6gesg7"},...]}
```

Remarque sur la reproductibilité. Après un second `concretize` dans un clone neuf, `git status` signale `spack/spack.lock` modifié. La comparaison des deux fichiers montre les mêmes hashes, la même version de Spack et les mêmes specs, seul l'ordre des deux racines change. Le contenu est identique.

Démonstration du buildcache, avec `zlib` comme cobaye puisque ce paquet ne fait pas partie de l'upstream. La première installation compile, la seconde extrait l'archive.

```
$ time spack -D . install
==> Installing gmake-4.4.1-ohsthau7wlphchdh2oa6oi2piplukjgk [5/6]
  Install: 19.57s.  Total: 20.22s
==> zlib: Successfully installed zlib-1.3.1-rlqkd7c
  Build: 7.10s.  Install: 2.42s.  Total: 12.30s
real    0m44.399s

$ spack -D . buildcache create -u --update-index local zlib
==> [1/4] Pushed gmake@4.4.1/ohsthau
==> [2/4] Pushed gcc-runtime@11.5.0/h25nzw4
==> [3/4] Pushed compiler-wrapper@1.0/ubrgzrg
==> [4/4] Pushed zlib@1.3.1/rlqkd7c
2.8M    /home/alban_pautre_gmail_com/bc-demo/mirror

$ spack -D . install --cache-only --no-check-signature
==> Extracting zlib-1.3.1-rlqkd7c from binary cache
==> zlib: Successfully installed zlib-1.3.1-rlqkd7c
  Fetch: 0.05s.  Install: 0.32s.  Total: 0.38s
real    0m2.150s
```

Quarante-quatre secondes contre deux secondes, pour un miroir de 2,8 Mo qui contient quatre paquets. Un second passage du script donne 38 s puis 5 s, l'ordre de grandeur est stable. L'option `-u` signe le cache comme non signé, d'où le `--no-check-signature` à la consommation. Dans l'environnement réel `spack/`, ce cache n'est pas utilisé, tout vient de l'upstream, qui est un cache déjà installé et donc encore plus rapide.

### Erreurs et résolutions

Première erreur, `spack concretize` répond `argument '--force' requires an environment`. Depuis Spack 1.x, un répertoire qui contient un `spack.yaml` n'est pas un environnement pour toutes les commandes. 

> Résolution, passer le répertoire avec `spack -D spack`.

Deuxième erreur, le premier `concretize` tente de construire clingo et patchelf, puis échoue sur `PermissionError: '/opt/apps/spack/var/spack/cache/blobs'`. Le cache de Spack est dans l'installation système, en lecture seule. 

> Résolution, `spack config add` sur `source_cache` et `misc_cache` vers `$HOME/.spack/cache`, puis `spack bootstrap now`. Les deux outils se téléchargent alors en binaire depuis le buildcache public en deux minutes.

Troisième erreur, qui est plus coûteuse, `spack install --cache-only` échoue avec `No binary found when cache-only was specified` et un avertissement `upstream not found: /opt/apps/spack/opt/spack/.spack-db/index.json`. Deux causes possibles : le buildcache public ne contient pas nos specs exactes, et surtout l'arbre d'installation du cluster est padded, le vrai chemin contient quatre niveaux de `__spack_path_placeholder__` avant `linux-x86_64_v3`, donc la base de données n'est pas là où je la cherchais. 

> Résolution, pointer l'upstream sur le chemin réel, les vingt paquets de l'environnement sont alors tous réutilisés.

Quatrième erreur, la cible. Sur le noeud de login, Spack détecte `zen2`, alors que la pile du cluster est installée pour `x86_64_v3`. Aucun hash ne correspond, donc il veut tout recompiler. 

> Résolution, écrire `target=x86_64_v3` dans les deux specs. Un `openmpi` compilé pour zen2 aurait aussi tourné sur les noeuds, mais il aurait été un second exemplaire inutile.

Cinquième erreur, moins grave, le réglage `packages: all: compiler` est déprécié depuis Spack 1.0 et ignoré, avec l'avertissement `has been deprecated in Spack v1.0, and is currently ignored`. 

> Résolution, supprimer ce bloc et choisir le compilateur dans la spec avec `%gcc`, ce que l'énoncé demande de toute façon.

### Réponses aux questions

**Quelle est la syntaxe `package@version%compiler+variant~variant` ? Donnez une spec complète pour hdf5 compilé avec GCC, MPI activé, Fortran activé, C++ désactivé**

```
hdf5@1.14.5%gcc@11.5.0+mpi+fortran~cxx
```

Le nom vient en premier, `@1.14.5` fixe la version (une plage comme `@1.14:` serait acceptée et laissée au concretizer), `%gcc@11.5.0` choisit le compilateur (la version est facultative), `+mpi` et `+fortran` activent deux variants (ce qui ajoute les dépendances correspondantes, ici le fournisseur MPI et un compilateur Fortran), `~cxx` désactive le variant C++ (donc pas d'interface C++). 

Le fournisseur MPI se précise avec une dépendance, par exemple `^openmpi@5.0.8`, sinon le concretizer prend le premier de sa liste de préférence. La spec complète et lisible donne `hdf5@1.14.5%gcc@11.5.0+mpi+fortran~cxx ^openmpi@5.0.8`.

---

**Pourquoi `spack.lock` suffit à reproduire l'environnement et pourquoi `spack.yaml` seul ne suffit pas ?**

`spack.yaml` décrit une intention, il donne des noms, des plages de versions, des variants souhaités, un compilateur, et des préférences. Il ne dit pas quelle version de chaque dépendance sera retenue, ni dans quel ordre, ni avec quels patches.

`spack.lock` décrit le résultat, pour chaque paquet, il donne la version exacte, la cible, le compilateur, tous les variants, les patches et le hash qui identifie le binaire. Il donne aussi le graphe des dépendances, paquet par paquet.

Une concretisation dépend du dépôt de recettes du jour, des préférences par défaut, de la machine et du compilateur. Le même `spack.yaml` concrétisé dans six mois peut choisir une version plus récente d'une dépendance et produire un autre graphe. `spack.lock` supprime cette liberté et vient péréniser la configuration dans le temps, `spack install` installe alors exactement ce qui est écrit, et le hash reste le même d'une machine à l'autre pour une même cible.

Les deux fichiers ne servent donc pas à la même chose, et c'est pour cela qu'on versionne les deux. Le yaml explique l'intention, le lock garantit le résultat, et le diff du lock dans une revue montre ce qui a réellement changé dans la pile.

---

**Quel intérêt du buildcache pour un pipeline qui installe l'environnement à chaque exécution ?**

Sans buildcache, chaque exécution repart des sources. OpenMPI et ses dépendances demandent des dizaines de minutes de compilation, à chaque pipeline pour un résultat toujours identique puisque le lock ne change pas. C'est du calcul pur perdu, et cela impose des runners puissants pour rien (on perd en coût de stockage mais on gagne en coût de build, ce qui est mieux car moins couteux).

Avec un buildcache, les paquets sont téléchargés en binaire puis installés par copie. L'étape passe de dizaines de minutes à quelques dizaines de secondes, et le pipeline peut se permettre de repartir d'un environnement propre à chaque exécution, ce qui est la seule façon d'être sûr que l'environnement décrit fonctionne encore.

Deux limites. Le cache doit contenir le hash exact, une spec différente ne correspond à aucun binaire et Spack retombe sur les sources. Et un buildcache accélère, il ne garantit rien et c'est le lock qui garantit. Un cache sans lock donne des installations rapides et non reproductibles.

### Bilan

Ce qui fonctionne : un environnement décrit par deux fichiers de soixante lignes, concrétisé en une minute et installé sans recompiler, avec cmake et OpenMPI prêts pour le projet.

Ce qui ne fonctionne pas : une installation complète depuis les sources n'est pas réaliste sur un noeud de login à un coeur, et le buildcache public ne contient pas les specs exactes de ce cluster, il faut donc fabriquer le sien puis le partager.

Ce que je referais autrement : vérifier la cible et le chemin réel de l'upstream avant de lancer la première installation, ces deux détails m'ont coûté trois essais. Et mettre le miroir en place dès la première installation, plutôt que de le découvrir après coup.

## Mission 5 (rendu)

Le dépôt est public, il se clone donc simplement :

```
git clone https://github.com/gnoooo/chps0902_devops
```

Le tag `seance-inversee` marque l'état rendu, carnet compris :

```
git tag -l
git checkout seance-inversee
```

Le carnet est le fichier `README.md` à la racine. Le code est dans `src/`, le pipeline dans `.github/workflows/ci.yml`, le script Slurm dans `slurm/` et l'environnement Spack dans `spack/`.

Les jobs `test_hpc` et `test_hpc_wait` ont besoin du runner auto-hébergé, qui vit sur le noeud de login. Le cluster est détruit en fin de séance pour ne pas payer, donc ces deux jobs ne peuvent plus tourner ensuite (pour éviter de tomber malencontreusement à court de crédits). Ils portent une condition sur la variable `HPC_RUNNER`, absente, et sortent donc en `skipped`. Les runs 39582070775 et 39582567650 cités en mission 3 viennent de l'ancien dépôt, nommé `chps0902_visualization_devops`, supprimé depuis, leurs logs sont recopiés dans le carnet.

Le dernier run vert de ce dépôt est le run 39604040524, sur le commit `39dd6af`, avec build et test réussis et les jobs HPC ignorés.

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

> Un pipeline qui construit, teste, analyse et empaquette un projet C et MPI, avec des artefacts et des dépendances entre jobs. Je sais maintenant pourquoi un test doit tourner dans le même environnement que la compilation, et pourquoi un binaire ne traverse pas deux distributions.
>
> Les déclencheurs : une règle par événement, une condition sur la référence, et un secret qui reste masqué dans les journaux même quand on l'affiche volontairement.
>
> Un runner auto-hébergé sur un noeud de login, et la raison de ce choix, ici un pare-feu qui n'accepte que IAP.
>
> La chaîne CI vers Slurm : soumettre avec `--parsable`, suivre l'état avec `sacct`, lire la raison d'attente avec `squeue -o %r`, distinguer un échec de code d'un échec d'infrastructure.
>
> Un environnement Spack décrit par deux fichiers, compris comme une intention plus un résultat, avec la réutilisation d'un upstream et l'idée du buildcache.

Points à retravailler :

> L'attente d'un job Slurm : `sbatch --wait` m'a donné une erreur alors que le job était vivant, je veux écrire un polling robuste avec un délai maximal propre à la file, distinct du wall-time.
>
> Le buildcache : j'ai fabriqué, poussé et consommé un miroir local pour un paquet. Il reste à le faire pour la pile complète, à le signer et à le partager entre plusieurs machines.
>
> Les variants MPI de Spack : choisir un fournisseur MPI avec `^openmpi`, et comprendre l'effet des variants `fortran`, `cuda` ou `internal-pmix` sur un vrai calcul.
>
> La lecture d'un `spack.lock` : le fichier fait soixante kilo-octets de JSON sur une ligne, je sais le comparer, pas encore l'utiliser pour expliquer un changement de pile en revue.
>
> Le coût : un cluster qui tourne sans calcul coûte de l'argent, et le réflexe de détruire en fin de séance doit devenir un automatisme, avec une vérification des instances restantes.

Usage dans mes activités CHPS :

> Pour un code de recherche, la valeur est de séparer deux choses qui se mélangent souvent, l'environnement et le code. Un `spack.yaml` et un `spack.lock` dans le dépôt disent avec quoi le calcul tourne, le carnet dit ce qui a été essayé et pourquoi.

> Pour un calcul lourd, la chaîne CI vers Slurm permet de tester petit sur un conteneur, puis de lancer le vrai calcul sur la partition adaptée, avec un journal et des artefacts qui restent.

> Pour un rendu ou une publication, le carnet et l'historique Git donnent la trace des erreurs, ce qui vaut mieux qu'un résultat propre sans explication.



