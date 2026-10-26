/**
 * Contrôles de sécurité, avec les mêmes outils et les mêmes versions que .github/workflows/securite.yml :
 *   securityScan(check: 'secrets')                    gitleaks sur le dépôt et son historique
 *   securityScan(check: 'dependances')                Trivy sur les dépendances du code (pom.xml)
 *   securityScan(check: 'dockerfile')                 Hadolint sur le Dockerfile des ressources
 *   securityScan(check: 'image', image: ref, block: true)   Trivy sur l'image, puis SBOM Syft (archivé)
 *
 * Les outils tournent dans leur propre conteneur, lancés par le démon de l'hôte (socket monté, comme pour la construction
 * de l'image). Pour qu'ils voient le dossier de travail de Jenkins, on partage les volumes du conteneur Jenkins
 * (--volumes-from) : le chemin est alors le même des deux côtés.
 *
 * ÉCRIT MAIS PAS EXÉCUTÉ dans ce laboratoire : le disque de la machine était plein quand ces étapes ont été ajoutées.
 * Seule la version GitHub Actions a tourné pour de vrai (voir le README).
 */
def call(Map cfg = [:]) {
    String check = cfg.check ?: error('securityScan : check est obligatoire')
    String trivy = 'aquasec/trivy:0.70.0'
    String cache = '-v trivy-cache:/root/.cache'
    String sock = '-v /var/run/docker.sock:/var/run/docker.sock'
    // Dans le conteneur Jenkins, le nom d'hôte est l'identifiant du conteneur.
    String shared = '--volumes-from "$(hostname)" -w "$PWD"'

    switch (check) {
        case 'secrets':
            // --redact : la valeur du secret n'apparaît jamais dans le journal. .gitleaks.toml (à la racine du dépôt
            // analysé) porte les exceptions.
            sh "docker run --rm ${shared} zricethezav/gitleaks:v8.30.1 git --redact --exit-code 1 ."
            break
        case 'dependances':
            // Rapport HIGH et CRITICAL, puis porte sur les CRITICAL corrigibles (même politique que GitHub Actions).
            sh "docker run --rm ${cache} ${shared} ${trivy} fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed ."
            sh "docker run --rm ${cache} ${shared} ${trivy} fs --scanners vuln --severity CRITICAL --ignore-unfixed --exit-code 1 ."
            break
        case 'dockerfile':
            writeFile file: 'Dockerfile.securite', text: libraryResource('docker/Dockerfile.jar')
            sh "docker run --rm -i hadolint/hadolint:v2.15.1 hadolint --failure-threshold warning - < Dockerfile.securite"
            break
        case 'image':
            String image = cfg.image ?: error("securityScan : image est obligatoire pour check: 'image'")
            boolean block = cfg.block != false
            sh "docker run --rm ${cache} ${sock} ${trivy} image --severity HIGH,CRITICAL --ignore-unfixed ${image}"
            // Dérogation consciente : block: false laisse passer, mais le journal garde le rapport ci-dessus.
            sh "docker run --rm ${cache} ${sock} ${trivy} image --severity CRITICAL --ignore-unfixed --exit-code ${block ? 1 : 0} ${image}"
            sh "docker run --rm ${sock} anchore/syft:v1.55.0 ${image} -o spdx-json > sbom.spdx.json"
            archiveArtifacts artifacts: 'sbom.spdx.json', allowEmptyArchive: true
            break
        default:
            error("securityScan : contrôle inconnu « ${check} »")
    }
}
