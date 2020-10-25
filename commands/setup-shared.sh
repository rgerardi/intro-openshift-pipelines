#!/bin/sh
PREFIX=$1

if [ -z "$PREFIX" ]; then
  PREFIX="hellogo"
fi

echo "Creating required projects"
oc new-project $PREFIX-cicd --display-name="CI/CD" --description="CI/CD demo using Openshift Pipelines"
oc new-project $PREFIX-hellogo-dev --display-name="Hellogo App DEV" --description="CI/CD demo using Openshift Pipelines - Go App DEV"
oc new-project $PREFIX-hellogo-qa --display-name="Hellogo App QA" --description="CI/CD demo using Openshift Pipelines - Go App QA"


echo "Applying permission to CI/CD service account to update the projects"
oc adm policy add-role-to-user edit system:serviceaccount:$PREFIX-cicd:pipeline -n $PREFIX-hellogo-qa
oc adm policy add-role-to-user edit system:serviceaccount:$PREFIX-cicd:pipeline -n $PREFIX-hellogo-dev


echo "Applying permission to allow project service account to pull image"
oc policy add-role-to-group system:image-puller system:serviceaccounts:$PREFIX-hellogo-qa --namespace=$PREFIX-cicd
oc policy add-role-to-group system:image-puller system:serviceaccounts:$PREFIX-hellogo-dev --namespace=$PREFIX-cicd
