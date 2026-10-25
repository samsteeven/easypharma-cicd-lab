/**
 * Analyse SonarQube avec le plugin Maven. À appeler après mavenBuild() : le rapport JaCoCo
 * (target/site/jacoco/jacoco.xml) est déjà produit, il n'y a donc pas de seconde exécution des tests.
 * « sonarqube » est le nom du serveur déclaré dans jenkins/casc/jenkins.yaml.
 */
def call(Map cfg = [:]) {
    String key = cfg.projectKey ?: error('sonarScan : projectKey est obligatoire')
    String name = cfg.projectName ?: key
    withSonarQubeEnv('sonarqube') {
        withEnv(['MAVEN_OPTS=-Xmx1024m -Dmaven.repo.local=/var/jenkins_home/.m2/repository']) {
            sh "./mvnw -B -ntp org.sonarsource.scanner.maven:sonar-maven-plugin:sonar " +
               "-Dsonar.projectKey=${key} -Dsonar.projectName='${name}'"
        }
    }
}
