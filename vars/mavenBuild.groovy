/**
 * Compile et lance les tests avec le wrapper Maven du projet (JDK 21 du conteneur Jenkins).
 * Le dépôt local Maven est dans le volume de Jenkins : le deuxième build ne retélécharge pas les dépendances.
 *
 * Paramètres (tous facultatifs) :
 *   goals    : objectifs Maven, défaut « clean verify »
 *   profile  : profil Spring des tests, défaut « test » (base H2 en mémoire, sans Docker)
 */
def call(Map cfg = [:]) {
    String goals = cfg.goals ?: 'clean verify'
    String profile = cfg.profile ?: 'test'
    withEnv([
        "SPRING_PROFILES_ACTIVE=${profile}",
        'MAVEN_OPTS=-Xmx1024m -Dmaven.repo.local=/var/jenkins_home/.m2/repository',
        // Le test de démarrage du contexte exige un secret JWT : valeur factice, propre aux tests.
        'JWT_SECRET=valeur-factice-pour-les-tests-uniquement-ne-jamais-utiliser-en-production-0123456789',
    ]) {
        sh "chmod +x mvnw && ./mvnw -B -ntp ${goals} -Dmaven.javadoc.skip=true"
    }
}
