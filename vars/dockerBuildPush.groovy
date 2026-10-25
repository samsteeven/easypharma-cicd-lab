/**
 * Construit l'image à partir du JAR déjà produit par mavenBuild() (« construire une fois, empaqueter ensuite ») et la
 * publie dans le registre. Le Dockerfile vient des ressources de la bibliothèque : l'application n'a pas à le connaître.
 *
 * Le client Docker parle au démon de l'hôte (socket monté dans le conteneur Jenkins) : « localhost:5000 » désigne donc
 * le registre publié sur l'hôte, celui que le cluster kind lira plus tard.
 */
def call(Map cfg = [:]) {
    String image = cfg.image ?: error('dockerBuildPush : image est obligatoire')
    String registry = cfg.registry ?: 'localhost:5000'
    String tag = cfg.tag ?: env.BUILD_NUMBER
    String ref = "${registry}/${image}:${tag}"

    writeFile file: 'Dockerfile.ci', text: libraryResource('docker/Dockerfile.jar')
    // Un seul JAR exécutable : on exclut l'archive « .original » que produit le plugin Spring Boot.
    String jar = sh(returnStdout: true, script: "ls target/*.jar | grep -v '.original' | head -1").trim()
    if (!jar) {
        error('dockerBuildPush : aucun JAR dans target/ (mavenBuild a-t-il tourné ?)')
    }
    sh "docker build -f Dockerfile.ci --build-arg JAR_FILE=${jar} --label org.opencontainers.image.revision=${env.GIT_SHORT ?: 'inconnu'} -t ${ref} ."
    sh "docker push ${ref}"
    echo "Image publiée : ${ref}"
    return ref
}
