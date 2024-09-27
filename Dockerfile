FROM tomcat:9.0-jdk17-corretto
COPY target/petclinic.war /usr/local/tomcat/webapps/
EXPOSE 8080
