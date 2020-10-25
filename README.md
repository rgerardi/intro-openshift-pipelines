# Introduction to OpenShift Pipelines Lab

In this lab, you'll learn and practice OpenShift Pipelines concepts in practice by developing a pipeline to build a deploy a small Go web application.

OpenShift Pipelines is a cloud native [CI/CD](https://en.wikipedia.org/wiki/Continuous_integration) solution that allows you to run your pipelines as containers directly within OpenShift. It's based on the open source project [Tekton](https://github.com/tektoncd/pipeline). For more information about OpenShift Pipelines, consult its [official documentation](https://docs.openshift.com/container-platform/4.5/pipelines/understanding-openshift-pipelines.html).

This lab assumes you're familiar with OpenShift / Kubernetes concepts, such as Pods, Services, Deployments, Routes, RBAC, and Operators. The lab does not provide basic information about OpenShift. For more information consult [OpenShift documentation](https://docs.openshift.com/).

## What you need

* A running OpenShift 4.4 or 4.5 cluster. OpenShift 4.5 is recommended. 
	* This lab does not provide OpenShift install instructions.
* `oc` command line tool
* `tkn` command line tool (optional)
* Text editor
* `git` and access to Github

You'll build the `hellogo` web application in this lab. You can find its source code at [https://github.com/rgerardi/hellogo](https://github.com/rgerardi/hellogo).

This lab was tested with CRC 1.17 with OpenShift 4.5.14 and RHPDS running OpenShift 4.4.

## Preparation

Before you start building the CI/CD pipeline using OpenShift pipelines, you need to prepare your environment. For this lab you need three OpenShift projects:

1. `cicd` - This project hosts the pipeline resources such as tasks and runs the pipeline
2. `hellogo-dev` - You'll deploy the application in this project simulating a DEV enviroment
3. `hellogo-qa` - Same as previous but simulating the QA environment.

Let's create the project in OpenShift. First, log in to your cluster using the `oc` command line tool or the web interface. Then, create the three required projects:

```
$ oc new-project cicd --display-name="CI/CD" --description="CI/CD demo using Openshift Pipelines"
$ oc new-project hellogo-dev --display-name="Hellogo App DEV" --description="CI/CD demo using Openshift Pipelines - Go App DEV"
$ oc new-project hellogo-qa --display-name="Hellogo App QA" --description="CI/CD demo using Openshift Pipelines - Go App QA"
```

***Note***: If you're using a shared cluster, such as RHPDS shared environment, prefix the project names with your initials or a random string to prevent conflicts, for example `rgerardi-cicd` instead of `cicd`. Adjust the commands accordingly.


Next, switch to the `cicd` project:

```
$ oc project cicd
Now using project "cicd" on server "https://api.crc.testing:6443".
```

By default, pipelines and tasks in OpenShift Pipelines run using the `pipeline` service account. Add permissions to allow the pipeline to create and manage OpenShift objects in other projects using this service account:

```
$ oc adm policy add-role-to-user edit system:serviceaccount:cicd:pipeline -n hellogo-qa
$ oc adm policy add-role-to-user edit system:serviceaccount:cicd:pipeline -n hellogo-dev
```

Finally, allow the other projects to pull images from the `cicd` project by providing the role `system:image-puller` to the service account group in the destination projects:

```
$ oc policy add-role-to-group system:image-puller system:serviceaccounts:hellogo-qa --namespace=cicd
$ oc policy add-role-to-group system:image-puller system:serviceaccounts:hellogo-dev --namespace=cicd
```

If you want to make modifications to the `hellogo` application source code for testing, then fork the project into your own Github account. If you just want to build it as is, you can use the original repo directly.

Finally, clone this repository [intro-openshift-pipelines](https://github.com/rgerardi/intro-openshift-pipelines) in your local machine to access the tasks and pipeline `yaml` definitions.

## Install OpenShift Pipelines

You can install OpenShift pipelines in your cluster by using the provided operator. If your cluster already has the Pipelines operator running you can skip this step. For example, the shared RHPDS cluster has the operator running.

### Using the Web UI

Log in to the web UI using the admin account.

Then open the Operator Hub by clicking on the menu "Operators -> Operator Hub":

![operator-hub](/pictures/operator-hub01.png)

Search for the Pipelines operator by typing "pipelines" in the search box. Then select the "OpenShift Pipelines Operator" entry:

![operator-hub-search](/pictures/operator-hub02.png)

Click in "Install" to open the installation screen:

![operator-hub-install](/pictures/operator-hub03.png)

Select the desired update channel according to your cluster version, for example "ocp-4.5", then click install again to install the operator:

![operator-hub-install-screen](/pictures/operator-hub04.png)

Wait a few seconds to complete the installation:

![operator-hub-install-done](/pictures/operator-hub05.png)

OpenShift Pipelines is installed.

### Using the Command Line

If you prefer, you can install OpenShift Pipelines operator using the `oc` command line. First, log in to your cluster using `oc` as admin. Then, create the subscription definition as `yaml` file:

```
$ vi sub-4.5.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: ocp-4.5
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: openshift-pipelines-operator.v1.0.1
```

Finally, apply it to the cluster using `oc create`:

```
$ oc create -f sub-4.5.yaml
```

Verify the Operator installation succeeded:

```
$ oc get subscriptions -n openshift-operators
NAME                              PACKAGE                           SOURCE             CHANNEL
openshift-pipelines-operator-rh   openshift-pipelines-operator-rh   redhat-operators   ocp-4.5
```

