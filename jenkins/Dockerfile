# Jenkins LTS (JDK 21) avec les plugins du laboratoire, la configuration par code (JCasC) et le client Docker.
FROM docker:27-cli AS docker-cli

FROM jenkins/jenkins:lts-jdk21
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc/ /usr/share/jenkins/casc/
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc
