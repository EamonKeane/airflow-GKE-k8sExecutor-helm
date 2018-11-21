#!/usr/bin/groovy
pipeline {
  agent {
    kubernetes {
      label 'airflow-k8s-executor'
      yamlFile 'jenkinsPodTemplate.yml'
    }
  }
  stages {
    stage('Checkout code') {
      steps {
        container('jnlp'){
          script{
            inputFile = readFile('Jenkinsfile.json')
            config = new groovy.json.JsonSlurperClassic().parseText(inputFile)
            containerTag = env.BRANCH_NAME + '-' + env.GIT_COMMIT.substring(0, 7)
            println "pipeline config ==> ${config}"
          } // script
        } // container('jnlp')
      } // steps
    } // stage
    stage ('Push airflow to Chart Museum'){
      steps{
        container('gcloud-helm'){
          //Push chart to chart musuem
          sh "helm repo add ${config.helm.repoName} ${config.helm.repo}"
          sh "sed -i.bak 's/tag:.*/tag: ${containerTag}/g' ${config.helm.helmFolder}/values.yaml"
          sh "sed -i.bak 's/version:.*/version: 0.2.0-$env.BRANCH_NAME-latest/g' ${config.helm.helmFolder}/Chart.yaml"
          sh "helm push ${config.helm.helmFolder}/ ${config.helm.repoName}"
          sh "sed -i.bak 's/version:.*/version: 0.2.0-${containerTag}/g' ${config.helm.helmFolder}/Chart.yaml"
          sh "helm push ${config.helm.helmFolder}/ ${config.helm.repoName}"
        }
      }
    }
  }
}
