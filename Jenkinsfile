#!/usr/bin/groovy

@Library('github.com/EamonKeane/jenkins-pipeline@master')

def pipeline = new io.estrado.Pipeline()

podTemplate(label: 'jenkins-pipeline',
    containers: [
        containerTemplate(name: 'jnlp', image: 'lachlanevenson/jnlp-slave:3.10-1-alpine', args: '${computer.jnlpmac} ${computer.name}', 
        resourceRequestCpu: '200m', resourceLimitCpu: '300m', resourceRequestMemory: '256Mi', resourceLimitMemory: '512Mi')
    ],
    volumes:[
        nfsVolume(mountPath: '/dags', serverAddress: '10.154.0.7', serverPath: '/dags', readOnly: false),
    ],
){
    node ('jenkins-pipeline') {

        checkout scm;
        pipeline.gitEnvVars();

        def inputFile = readFile('Jenkinsfile.json')
        def config = new groovy.json.JsonSlurperClassic().parseText(inputFile)
        println "pipeline config ==> ${config}"
        if (env.BRANCH_NAME != "${config.buildBranch}") {
            println "Stopping the build.";
            return;
        }
        // Copy the github files
        sh "cp -a ${WORKSPACE}/${config.githubDagSubFolder}/. ${config.containerDagMountPath}"
        }
}
