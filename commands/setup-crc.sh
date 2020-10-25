#!/bin/sh
echo "Creating required projects"
oc new-project cicd --display-name="CI/CD" --description="CI/CD demo using Openshift Pipelines"
oc new-project hellogo-dev --display-name="Hellogo App DEV" --description="CI/CD demo using Openshift Pipelines - Go App DEV"
oc new-project hellogo-qa --display-name="Hellogo App QA" --description="CI/CD demo using Openshift Pipelines - Go App QA"


echo "Applying permission to CI/CD service account to update the projects"
oc adm policy add-role-to-user edit system:serviceaccount:cicd:pipeline -n hellogo-qa
oc adm policy add-role-to-user edit system:serviceaccount:cicd:pipeline -n hellogo-dev


echo "Applying permission to allow project service account to pull image"
oc policy add-role-to-group system:image-puller system:serviceaccounts:hellogo-qa --namespace=cicd
oc policy add-role-to-group system:image-puller system:serviceaccounts:hellogo-dev --namespace=cicd
