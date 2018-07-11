#!/usr/bin/groovy

@Library('github.com/EamonKeane/jenkins-pipeline@master')

def pipeline = new io.estrado.Pipeline()

def inputFile = readFile('dag-jenkins/Jenkinsfile.json')
def config = new groovy.json.JsonSlurperClassic().parseText(inputFile)

podTemplate(label: 'jenkins-pipeline',
    containers: [
        containerTemplate(name: 'jnlp', image: 'lachlanevenson/jnlp-slave:3.10-1-alpine', args: '${computer.jnlpmac} ${computer.name}', 
        resourceRequestCpu: '200m', resourceLimitCpu: '300m', resourceRequestMemory: '256Mi', resourceLimitMemory: '512Mi')
    ],
    imagePullSecrets: [
        'logistio-deploy-pull-secret'
    ],
    volumes:[
        hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
        secretVolume(secretName:'deploy-service-account', mountPath: '/home/jenkins/deploy-service-account'),
        nfsVolume(mountPath: $containerDagMountPath, serverAddress: $config.nfs.internalIP, serverPath: $config.nfs.dagFolder, readOnly: false),
    ],
    envVars:[
        secretEnvVar(key: 'docker_password', secretName: 'logistio-deploy-pull-password', secretKey: 'docker_password'),
    ],
){

    node ('jenkins-pipeline') {
        checkout scm;
        pipeline.gitEnvVars();

        if (env.BRANCH_NAME != 'master') {
            println "Stopping the build.";
            return;
        }
        // Move the service account file we mounted in the podTemplate construct
        sh "cp -r ${WORKSPACE} ${containerDagMountPath}"
        