# Laboratoire CI/CD autour d'EasyPharma

[![Pipeline GitHub Actions](https://github.com/samsteeven/easypharma-cicd-lab/actions/workflows/pipeline.yml/badge.svg)](https://github.com/samsteeven/easypharma-cicd-lab/actions/workflows/pipeline.yml)
[![Sécurité](https://github.com/samsteeven/easypharma-cicd-lab/actions/workflows/securite.yml/badge.svg)](https://github.com/samsteeven/easypharma-cicd-lab/actions/workflows/securite.yml)

Le même pipeline (build et 75 tests, analyse SonarQube avec porte qualité, image Docker) écrit **trois fois** : pour **Jenkins** (`Jenkinsfile` déclaratif et bibliothèque partagée Groovy), pour **GitLab CI** et pour **GitHub Actions**, puis déployé sur un cluster **Kubernetes local (kind)** avec un **chart Helm** synchronisé par **ArgoCD**.

L'application est le backend Spring Boot de [`easypharma-backend-lab`](https://github.com/samsteeven/easypharma-backend-lab) : ce dépôt ne la modifie pas, il la clone. Il ne contient que la définition des pipelines et du déploiement.

![Jenkins : vue des étapes sur trois builds](docs/jenkins-pipeline.png)

```
                    ┌────────── Jenkins ──────────┐
 easypharma-        │ build + tests ─ SonarQube ─ porte qualité ─ image Docker ─┐
 backend-lab  ─────►├────────── GitLab CI ────────┤                            ├─► registre local :5001
 (cloné)            ├────────── GitHub Actions ───┘ (sans Sonar, image sur GHCR)│
                    └─────────────────────────────┘                            │
                                                                               ▼
        Git (deploy/helm/easypharma/values.yaml : image.tag) ──► ArgoCD ──► kind (backend, PostGIS, Redis, RabbitMQ, MailHog)
```

## Ce qui est vérifié, et ce qui ne l'est pas

| Élément | Vérifié | Limites à connaître |
|---|---|---|
| Jenkins | 3 builds : 1 échec instructif (voir [Incidents](#incidents-rencontrés)), 2 succès (164 s et 171 s) ; configuration entièrement par code | build exécuté **dans le conteneur Jenkins** (pas d'agents distincts) ; un seul nœud ; plugins en versions flottantes |
| SonarQube | analyse et porte qualité attendue par Jenkins et par GitLab CI | **la porte est verte parce qu'elle ne juge que le nouveau code** (première analyse) ; voir [le constat](#sonarqube-la-porte-verte-qui-ne-prouve-rien) |
| GitLab CI | `.gitlab-ci.yml` validé par le schéma, 3 jobs réussis | exécuté avec **`gitlab-ci-local`**, un émulateur, **pas sur un vrai GitLab** : je ne peux rien affirmer sur les runners partagés, les files d'attente, l'interface ni les environnements GitLab |
| GitHub Actions | 2 runs réussis (cache vide, puis cache chaud), image publiée sur GHCR | pas d'étape SonarQube : mon serveur est local, injoignable depuis les runners GitHub |
| Helm + ArgoCD | déploiement, correction de dérive, déploiement de version par commit, mesurés | un seul nœud kind, pas de webhook Git, pas d'Ingress ni de TLS |
| Sécurité (DevSecOps) | secrets, Dockerfile, chart, dépendances et image analysés ; sur **GitHub Actions** : essai dans kind, SBOM, signature vérifiée ; sur **Jenkins** (build n°4, 408 s) et **GitLab CI émulé** : mêmes contrôles et même porte, publication de l'image dans le registre local (voir [Sécurité](#sécurité-devsecops)) | pas d'essai kind ni de signature dans Jenkins et GitLab CI ; pas de SBOM dans GitLab CI ; `root` pour Jenkins (accès au socket Docker), webhooks SonarQube non validés : **laboratoire local seulement** |

## Les mesures

Même application, mêmes étapes, **portable Windows 11**, Docker limité à 8 Go, une mesure par ligne (sauf indication). Les durées sont celles de chaque outil ; elles ne sont **pas strictement comparables** (machine locale contre runners GitHub, caches différents).

| | Jenkins (local) | GitLab CI (émulé, local) | GitHub Actions (runners GitHub) |
|---|---|---|---|
| **Build et tests, cache vide** | 188,6 s (étape) | 198 s (Maven « Total time » 3:18) | 84 s (étape) |
| **Build et tests, cache chaud** | 70,3 s, puis 81,3 s | non mesuré (voir ci-dessous) | 54 s |
| **Analyse SonarQube** | 49,4 s à froid, 36,7 s et 43,0 s à chaud | 88 s (Maven, attente de la porte comprise) | absente |
| **Porte qualité** | 9,5 s et 7,6 s (après correction du webhook) ; **expirée à 301 s** au premier build | comprise dans l'étape précédente (`sonar.qualitygate.wait`) | absente |
| **Image Docker** | 38,4 s, puis 26,3 s (image de base déjà là) | non mesurable (plomberie de l'émulateur) | 13 s puis 16 s (étape) |
| **Pipeline complet** | **164,1 s** et **171,3 s** (à chaud) ; 555 s en échec (1er build) | **1 527 s (25 min)** | **135 s** (cache vide), **104 s** (cache chaud) |
| Mémoire au repos | Jenkins 0,4 à 1 Go, SonarQube 2,1 à 2,3 Go | conteneur de l'outil ≈ 100 Mo + conteneurs des jobs | 0 en local |
| Lignes de configuration (hors lignes vides et commentaires) | 105 (Jenkinsfile + bibliothèque) + 78 (serveur : Dockerfile, plugins, JCasC) + 65 (Compose) | **58** | 86 |

**Pourquoi GitLab local affiche 25 minutes.** Ce n'est pas GitLab : l'émulateur copie le cache Maven (5 083 fichiers) et les artefacts **dans et hors** de chaque conteneur de job. Le détail relevé dans son journal : création du cache 3,8 min, import du cache 2,1 min (job Sonar) puis 4,6 min (job image), export des artefacts 1,2 min. Les scripts eux-mêmes (Maven 3 min 18 s puis 1 min 28 s) sont comparables aux autres colonnes ; tout le reste est de la plomberie propre à `gitlab-ci-local` sur Windows. **Ces 25 minutes ne disent rien sur la vitesse de GitLab CI.**

### Ce que j'ai vraiment constaté, outil par outil

**Jenkins**
- La configuration **par code est possible de bout en bout** (utilisateur, bibliothèque, serveur SonarQube, job), mais elle demande **trois couches** : image + plugins, JCasC, et Job DSL pour le job. Aucune saisie dans l'interface.
- La **bibliothèque partagée** (`vars/mavenBuild.groovy`, `sonarScan.groovy`, `dockerBuildPush.groovy`, plus le Dockerfile en ressource) garde le `Jenkinsfile` lisible : les étapes y sont des appels d'une ligne. En contrepartie, **le code de la bibliothèque est chargé depuis Git** : pour tester un changement, il faut le pousser. Le linter déclaratif du serveur (`scripts/jenkins-lint.sh`) rattrape les erreurs du `Jenkinsfile`, pas celles du Groovy de la bibliothèque.
- Au redémarrage, JCasC **recrée le job sans ses paramètres** (ils ne sont connus qu'après une première exécution) : mon script de déclenchement a dû gérer les deux URL.
- Il faut **un serveur à faire vivre** : 0,4 à 1 Go de mémoire au repos, des plugins à tenir à jour, un socket Docker à protéger.

**GitLab CI**
- **Un seul fichier**, `needs`, `artifacts` et `cache` sont des mots-clés du langage : le même pipeline tient en 58 lignes contre 105 + 78 pour Jenkins (le serveur Jenkins en plus).
- `-Dsonar.qualitygate.wait=true` fait attendre le verdict **par scrutation depuis le job** : aucun webhook à déclarer, donc pas l'incident qui m'a coûté 5 minutes chez Jenkins.
- Je n'ai **pas** pu juger : l'interface, les runners partagés, le délai avant démarrage d'un job, les pipelines de merge request, les environnements.

**GitHub Actions**
- Le plus rapide ici (104 à 135 s) et **sans rien à héberger** ; le cache Maven se règle en une ligne (`cache: maven`). Passer le JAR d'un job à l'autre exige un **artefact** explicite.
- Les deux dépôts sont clonés à la main (le dépôt du pipeline et celui de l'application), ce qui rend le workflow plus long (86 lignes).
- Absence d'étape SonarQube : un serveur local n'est pas joignable ; il faudrait SonarCloud ou un serveur exposé.

### SonarQube : la porte verte qui ne prouve rien

La porte qualité par défaut (« Sonar way ») ne juge que le **nouveau code**. À la première analyse, il n'y a pas de nouveau code : **elle passe**, et elle a passé dans les trois outils. Pourtant le même tableau de bord indique, pour l'ensemble du code, **couverture 28,7 %, 2 problèmes de sécurité (note D) et 2 de fiabilité (note E)**, que je n'ai pas triés.

| Onglet « New Code » | Onglet « Overall Code » |
|---|---|
| ![](docs/sonarqube-nouveau-code.png) | ![](docs/sonarqube-code-global.png) |

Une porte qualité n'a de valeur que si ses conditions sont choisies : seuil de couverture, nombre d'issues bloquantes. Ici, je n'ai pas défini de politique.

## Kubernetes : kind, Helm, ArgoCD

![ArgoCD : application synchronisée et saine](docs/argocd-application.png)

Le chart `deploy/helm/easypharma/` déploie le backend et ses dépendances (PostGIS, Redis, RabbitMQ, MailHog) avec des sondes Actuator, des limites de mémoire et un conteneur d'initialisation qui attend PostgreSQL. Le secret (`JWT_SECRET`, mots de passe) est créé **hors de Git** par `scripts/k8s-secrets.sh`.

ArgoCD surveille `deploy/helm/easypharma` sur la branche `main` ; un commit qui change `image.tag` est un déploiement.

| Mesure | Résultat |
|---|---|
| Création du cluster kind (un nœud) | 1 min 50 s |
| Installation d'ArgoCD (version 3.5.6 fixée) | 88 s |
| Premier déploiement, de la déclaration de l'application à `Synced/Healthy` | environ 1 min 30 s (relevé toutes les 10 s) |
| **Correction d'une dérive** (je passe le Deployment à 3 réplicas à la main) | **4 s** pour revenir à 1 |
| **Déploiement d'une nouvelle version** (commit du tag d'image, puis poussée) | **163 s** avant que le cluster demande la nouvelle image, **186 s** avant que le pod soit prêt |

**Le délai de 163 s est surtout de l'attente** : ArgoCD interroge Git, par défaut environ toutes les 3 minutes (je n'ai pas modifié ce réglage), et je n'ai pas de webhook (le cluster est local). Une première détection a pris 67 s, selon le moment du cycle. Avec un webhook GitHub, le délai tomberait au temps de démarrage du pod.

L'image déployée a été publiée dans le registre local par Jenkins (`b7e8c2c-2`), puis le déploiement suivant a utilisé celle de GitLab CI (`b7e8c2c-1000`) : les deux pipelines produisent une image que le cluster sait lancer.

## Sécurité (DevSecOps)

Des contrôles de sécurité sont intégrés au pipeline, avec une règle simple : **ce qui bloque est écrit, ce qui est toléré est écrit aussi, avec sa raison**. Ils ont tous tourné pour de vrai, mais pas tous partout :

- **GitHub Actions** (`securite.yml`, `pipeline.yml`) : tout, y compris l'essai de déploiement dans kind, le SBOM et la signature Cosign.
- **Jenkins** (`vars/securityScan.groovy`, build n°4 : succès en 408 s) : gitleaks, Trivy sur les dépendances, Hadolint, SonarQube et sa porte, Trivy sur l'image avec la même porte et les mêmes exceptions, SBOM Syft (SPDX, 297 paquets) archivé, publication. **Pas d'essai kind ni de signature.**
- **GitLab CI, émulé** (`gitlab-ci-local`, 31 minutes, code de sortie 0) : gitleaks, Trivy dépendances, Hadolint, SonarQube (porte `PASSED`), Trivy sur l'image avec la même porte, publication. **Pas de SBOM, pas d'essai kind, pas de signature.** Rappel : ce n'est pas un vrai GitLab.

Les tableaux ci-dessous décrivent les résultats du premier passage de chaque contrôle.

| Contrôle | Outil | Où | Ce qui s'est vraiment passé |
|---|---|---|---|
| Secrets dans le code **et l'historique** | gitleaks 8.30.1 (empreinte SHA-256 vérifiée) | `securite.yml` | Premier passage **rouge** : 3 constats, tous l'identifiant par défaut `admin:admin` de SonarQube que `scripts/bootstrap-sonar.sh` utilise une fois pour le remplacer. Ce n'est pas un secret : exception **étroite** dans `.gitleaks.toml` (ce fichier, cette valeur). Aucun autre constat dans l'historique. |
| Qualité du Dockerfile | Hadolint | `securite.yml` | Passe au seuil « warning ». |
| Configuration Dockerfile et Helm | Trivy (config) | `securite.yml` | Premier passage **rouge** : 13 constats HIGH (5 × `KSV-0014`, 8 × `KSV-0118`), **aucun sur le conteneur backend**. Le conteneur d'attente de PostgreSQL a été corrigé. Les 4 services tiers (PostgreSQL, Redis, RabbitMQ, MailHog) sont des **exceptions documentées** dans `.trivyignore.yaml`. |
| Dépendances du code | Trivy (fs, `pom.xml`) | `securite.yml` | **4 HIGH** corrigibles : `org.postgresql:postgresql` 42.7.8 (2 failles, corrigées en 42.7.11 et 42.7.12) et `spring-boot-starter-actuator` 3.5.7 (2 contournements d'authentification, corrigés en 3.5.12). Aucune CRITICAL : la porte passe. |
| Image Docker | Trivy (image) | `pipeline.yml` | Avec Spring Boot 3.5.7 : **53 failles corrigibles dans le JAR (43 HIGH, 10 CRITICAL)**, la porte était rouge et bloquait la publication. Après la montée de version du backend (voir ci-dessous) : **9** (7 HIGH, 2 CRITICAL), dont 2 CRITICAL sans correctif possible en Spring Framework 6.2, mises en **exceptions datées** ; la porte passe. |
| Essai de déploiement | kind + Helm, dans le job | `pipeline.yml` | Le chart durci (UID 10001 non root, système de fichiers en lecture seule, sans élévation de privilèges, `capabilities: drop ALL`, seccomp) démarre : backend prêt en moins d'une minute. |
| Isolation réseau | NetworkPolicy + mesure | `pipeline.yml` | Mesurée : un pod étranger **ne joint pas** PostgreSQL, un pod portant les étiquettes du backend le joint (témoin). kindnet applique donc les NetworkPolicy. Seul le trafic **entrant** est restreint. |
| SBOM | Syft (SPDX JSON) | `pipeline.yml` | Produit pour l'image publiée, conservé comme artefact. |
| Signature | Cosign « sans clé » (OIDC de GitHub) | `pipeline.yml` | Image **signée par son condensat**, SBOM attesté, et `cosign verify` réussi dans le pipeline. La signature prouve **quel workflow** a produit l'image, pas que l'image est sans faille. |
| Mises à jour | Dependabot | `.github/dependabot.yml` | Actions GitHub et image de base, chaque semaine. |
| Avant le commit | pre-commit (gitleaks, hadolint) | `.pre-commit-config.yaml` | **Non essayé.** Le même gitleaks a tourné dans les trois pipelines. |

### La politique, et ce qu'elle a donné

- **Bloquent** : tout secret détecté ; les constats HIGH et CRITICAL du Dockerfile et du chart (hors exceptions) ; les failles **CRITICAL pour lesquelles un correctif existe**, dans les dépendances et dans l'image.
- **Rapportées sans bloquer** : les HIGH des dépendances et de l'image. Bloquer dessus garderait le contrôle rouge tant que l'équipe du backend n'a pas mis ses dépendances à jour, et ce dépôt ne modifie pas l'application.
- **Dérogation consciente** : `bloquer` décoché au lancement manuel de `pipeline.yml`. Elle est visible dans l'exécution, et le rapport complet reste dans le journal. Je l'ai utilisée une fois pour aller au bout du pipeline (essai, publication, SBOM, signature) pendant que l'image avait 10 CRITICAL. **Sans elle, la publication était refusée** (exécution rouge, étapes suivantes ignorées), et c'est le comportement par défaut.
- **Exceptions datées** (`.trivyignore.yaml`, section `vulnerabilities`) : `CVE-2026-47884` (XsltView) et `CVE-2026-47890` (flux SSE), toutes deux CRITICAL dans `spring-webmvc`, **sans correctif publié pour Spring Framework 6.2** (corrigées seulement en 7.0.9, donc avec Spring Boot 4). Le backend n'utilise ni XsltView ni les SSE (recherche dans `src` et `pom.xml`). Chaque exception expire le 2027-01-31 et la porte redevient rouge si on ne la revoit pas.

### Ce que ça a montré

- **L'analyse du `pom.xml` voit 4 failles, l'analyse de l'image en voit 53.** Le fichier de dépendances ne liste que les versions déclarées ; le JAR contient aussi les dépendances transitives (Netty, Tomcat, Spring Security...). Analyser seulement le `pom.xml` donne une fausse tranquillité.
- **Corriger vaut mieux que contourner, mais ne suffit pas toujours.** Un seul changement de version de Spring Boot (3.5.7 vers 3.5.16, même version mineure) a fait passer l'image de 53 à 23 failles ; épingler quatre bibliothèques gérées par Spring Boot les a ramenées à 9. Il restait 2 CRITICAL qu'aucune version de la branche 6.2 ne corrige : là, la bonne réponse n'est pas de baisser le seuil mais d'écrire une exception datée, motivée, vérifiée contre le code.
- **Durcir un pod casse des choses qu'on ne soupçonne pas.** Le premier essai de déploiement est resté 5 minutes en attente : avec l'UID 10001, qui n'a pas d'entrée dans `/etc/passwd` de l'image PostgreSQL, `pg_isready` répond « no attempt » au lieu de se connecter. Corrigé par `-U postgres`. Sans l'essai dans un vrai cluster, ce chart durci aurait été remis à ArgoCD sans avoir démarré.
- **Le coût** : l'exécution complète de `pipeline.yml` dure 4 min 50 s, contre 104 à 135 s avant ces contrôles (job de l'image : environ 3,5 minutes).

### Ce qui n'est pas couvert

- **Corrections faites dans le backend** ([PR n°1 de `easypharma-backend-lab`](https://github.com/samsteeven/easypharma-backend-lab/pull/1), 75 tests verts) : Spring Boot 3.5.7 vers 3.5.16, et versions de Netty, Tomcat, driver PostgreSQL et Jackson épinglées par leurs propriétés. Ce dépôt ne modifie toujours pas l'application : tant que cette PR n'est pas fusionnée, le pipeline lancé sur `main` construit l'ancienne version et reste rouge ; lancé sur la branche `deps/spring-boot-3.5.16`, il est vert avec la porte active.
- **7 HIGH restent** dans l'image (dont protobuf 3.23.2, un client RabbitMQ, le driver SQL Server) : rapportées, pas bloquantes, non corrigées.
- **Pas d'analyse statique du code dans GitHub Actions** (SonarQube n'y est pas), pas de CodeQL, pas de test dynamique (DAST).
- **SonarQube a été trié** (voir ci-dessous) mais **rien n'est corrigé côté SonarQube** : la couverture reste à 28,7 % et les 4 constats sont ouverts.
- **Services tiers non durcis** (PostgreSQL, Redis, RabbitMQ, MailHog démarrent en root) ; pas de NetworkPolicy sortante ; pas de Pod Security Admission ; secrets créés à la main dans le cluster.
- **La signature n'est pas vérifiée à l'admission** : rien n'empêche le cluster de lancer une image non signée (il faudrait Kyverno ou une règle équivalente).
- **Jenkins et GitLab CI** : la signature sans clé repose sur l'OIDC de GitHub ; ces deux outils demanderaient une paire de clés ou leur propre jeton OIDC, non mis en place. Le SBOM n'est produit que par GitHub Actions et Jenkins.

### Triage des 4 problèmes de SonarQube

Analyse refaite sur le backend corrigé : porte **verte**, couverture **28,7 %**, mêmes 2 problèmes de sécurité (note D) et 2 de fiabilité (note E). Lus dans le code :

| Constat | Verdict |
|---|---|
| `S4502` CSRF désactivé (`WebSecurityConfig`, critique) | **Acceptable** : API sans session, jeton dans l'en-tête `Authorization`, aucun cookie. |
| `S5122` CORS ouvert à toutes les origines (« pour le dev ») | **Corrigé** ([PR n°3 du backend](https://github.com/samsteeven/easypharma-backend-lab/pull/3)) : origines lues dans `app.cors.allowed-origins`, test qu'une origine inconnue est rejetée. |
| `S2229` ×2, `@Transactional` ignoré (`EmployeePermissionService`) | **Vrai mais surévalué** (« bloquant ») : l'appel sur `this` contourne le proxy, mais `employee_id` est unique, donc pas de doublon possible. Corrigé dans la même PR. |

Deux points que SonarQube ne signale pas, lus en passant et **non corrigés** : `/actuator/**` et `/h2-console/**` sont ouverts à tous dans la configuration de sécurité, et `metrics` et `prometheus` sont exposés dans tous les profils.

## Incidents rencontrés

Chacun a été corrigé et reste visible dans l'historique Git.

1. **Port 5000 refusé** : Windows réserve ce port ; le registre est publié sur **5001**.
2. **Porte qualité expirée (build n°1 de Jenkins, 5 minutes perdues)** : SonarQube refuse par défaut les webhooks vers des adresses privées, donc vers le réseau Docker (*« Invalid URL: loopback, wildcard, link-local, site-local… »*). Jenkins n'était jamais prévenu. Corrigé avec `sonar.validateWebhooks=false`, acceptable seulement en local.
3. **Déclenchement refusé (HTTP 400)** : un job paramétré n'accepte plus l'URL `build`, et après un redémarrage JCasC le recrée sans paramètres. Deux fois, mon script a attendu un build inexistant.
4. **`gitlab-ci-local` introuvable sous Windows** : il exige `rsync`. Il tourne donc dans un conteneur (`gitlab/Dockerfile`) qui pilote le Docker de l'hôte.
5. **Docker bloqué pendant le run GitLab** : Jenkins, SonarQube et un job Maven ensemble ont dépassé les 8 Go ; il a fallu redémarrer Docker Desktop. D'où les **phases** : la pile Jenkins et SonarQube, puis le cluster, jamais ensemble.
6. **Backend en `DOWN` dans Kubernetes** : l'application attend RabbitMQ et un serveur SMTP, que mon premier chart ne déployait pas. Ajoutés, au lieu de masquer les indicateurs de santé.
7. **Backend qui plante au premier démarrage** : il démarrait avant PostgreSQL ; ajout d'un conteneur d'initialisation.
8. **Dossier `app/` ajouté par erreur au dépôt** : c'est le clone de l'application recopié par l'émulateur. Retiré du commit avant qu'il ne serve, et ignoré par Git.
9. **`Jenkinsfile` invalide, trouvé seulement en l'exécutant** : une apostrophe non échappée dans une description de paramètre, ajoutée avec les étapes de sécurité alors que je ne pouvais pas les lancer. Le linter du serveur l'a refusée ; `main` est resté cassé jusqu'à la PR n°9.
10. **Jeton SonarQube périmé, deux fois (HTTP 401)** : `bootstrap-sonar.sh` gardait le jeton de `.env`, que le serveur recréé ne connaissait plus ; le fichier `.gitlab-ci-local-variables.yml` recopié à la main avait le même défaut. Les scripts régénèrent maintenant le jeton ou le fichier.
11. **gitleaks voyait deux historiques dans Jenkins** : le dossier de travail contient celui de ce dépôt (le `Jenkinsfile`) et celui de l'application. 4 constats au lieu de 1 ; l'analyse est limitée à `--log-opts=HEAD`.
12. **Un vrai secret par défaut dans l'application** : `scripts/run-tests.ps1` du backend contenait une valeur fixe pour `JWT_SECRET` (commit `81d94d7`). Le script génère maintenant un secret jetable ; la valeur reste dans l'historique, listée dans `.gitleaksignore` du backend. **Je n'ai pas pu établir si elle a servi ailleurs que pour les tests locaux.**
13. **Disque C: plein pendant l'analyse de l'image (11 Mo libres)** : Docker et Jenkins se sont figés. Supprimer des images ne rend rien à Windows : `docker_data.vhdx` ne rétrécit pas seul, il a fallu compacter le disque virtuel. À prévoir avant de lancer cette pile sur un poste serré.

## Démarrer

Prérequis : Docker (8 Go), `kind`, `helm`, `kubectl`, `gh`.

```bash
python scripts/make-env.py                   # mots de passe aléatoires dans .env (ignoré par git)

# Phase 1 : Jenkins, SonarQube, registre
docker compose up -d registry sonar-db sonarqube
bash scripts/bootstrap-sonar.sh              # mot de passe, jeton d'analyse, webhook
docker compose up -d --build jenkins         # http://localhost:8080 (admin, mot de passe dans .env)
bash scripts/jenkins-lint.sh                 # valide le Jenkinsfile
bash scripts/jenkins-run.sh                  # lance le pipeline et affiche la durée des étapes
bash scripts/gitlab-local.sh                 # le même pipeline avec gitlab-ci-local
docker compose stop jenkins sonarqube sonar-db   # libère 3 Go

# Phase 2 : cluster et GitOps
bash scripts/kind-up.sh                      # cluster kind relié au registre
bash scripts/k8s-secrets.sh                  # secret du cluster (valeurs aléatoires, hors Git)
bash scripts/argocd-install.sh               # ArgoCD 3.5.6 et application EasyPharma
kubectl --context kind-easypharma -n easypharma port-forward svc/easypharma-backend 8080:8080
```

GitHub Actions : `gh workflow run pipeline.yml`.

## Limites

- **GitLab CI n'a pas tourné sur GitLab** (voir le tableau du haut).
- **Le `.gitlab-ci.yml` n'est pas prêt pour GitLab.com tel quel** : le job `image-docker` suppose un socket Docker monté (runner local ; sur les runners partagés il faudrait docker-in-docker ou Kaniko et le registre du projet), et le job Sonar vise un serveur local (`host.docker.internal`).
- Un nœud Jenkins qui exécute les builds lui-même, en `root` ; un seul nœud kind ; pas de webhook Git ; pas de TLS ni d'Ingress.
- Les durées sont des mesures isolées sur une seule machine. Elles montrent des ordres de grandeur, pas un classement des outils.
- Les 75 tests du backend tournent sur H2 : le pipeline ne teste pas PostgreSQL ni SQL Server (voir `easypharma-backend-lab`).
- Le registre local est en HTTP. L'image du lab local (Jenkins, GitLab CI) n'est ni signée ni vérifiée ; l'analyse et la signature n'ont tourné que sur GitHub Actions.
- L'image déployée dans le cluster n'est pas mise à jour automatiquement par la CI : le changement de `image.tag` est un commit manuel. Un pipeline réel l'écrirait lui-même (avec un jeton d'écriture sur le dépôt).
- Les secrets de production (External Secrets, Sealed Secrets) ne sont pas traités.

## Structure

```
Jenkinsfile                   pipeline déclaratif
vars/ resources/              bibliothèque partagée Groovy (étapes, dont securityScan, et Dockerfile)
jenkins/                      Dockerfile, plugins et configuration JCasC du serveur
docker-compose.yml            Jenkins, SonarQube, registre (phase 1)
.gitlab-ci.yml  gitlab/       GitLab CI et le conteneur gitlab-ci-local
.github/workflows/            GitHub Actions : pipeline.yml (build, image, essai, SBOM, signature), securite.yml (contrôles)
.gitleaks.toml .trivyignore.yaml   exceptions acceptées, avec leur raison
.github/dependabot.yml  .pre-commit-config.yaml
deploy/helm/easypharma/       chart Helm
argocd/application.yaml       application ArgoCD
kind/  scripts/               cluster kind et scripts (voir « Démarrer »)
docs/                         captures d'écran réelles
```
