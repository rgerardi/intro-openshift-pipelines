# Introduction to OpenShift Pipelines Lab

In this lab, you'll learn and practice OpenShift Pipelines concepts in practice by developing a pipeline to build a deploy a small Go web application.

OpenShift Pipelines is a cloud native [CI/CD](https://en.wikipedia.org/wiki/Continuous_integration) solution that allows you to run your pipelines as containers directly within OpenShift. It's based on the open source project [Tekton](https://github.com/tektoncd/pipeline). For more information about OpenShift Pipelines, consult its [official documentation](https://docs.openshift.com/container-platform/4.5/pipelines/understanding-openshift-pipelines.html).

This lab assumes you're familiar with OpenShift / Kubernetes concepts, such as Pods, Services, Deployments, Routes, RBAC, and Operators. The lab does not provide basic information about OpenShift. For more information consult [OpenShift documentation](https://docs.openshift.com/).

In this lab you'll define a CI/CD pipeline to build the `hellogo` web application then deploy it in the DEV and QA environments. You can find the application source code at [https://github.com/rgerardi/hellogo](https://github.com/rgerardi/hellogo).

To build this pipeline, you'll use OpenShift Pipelines objects such as Steps, Tasks, Cluster Tasks, Pipelines, and Pipeline Runs.  You can find more details about these objects in the [documentation](https://docs.openshift.com/container-platform/4.5/pipelines/understanding-openshift-pipelines.html). At the end, your pipeline will look like this:

![pipeline-final](/pictures/pipeline-final.png)

## What you need

* A running OpenShift 4.4 or 4.5 cluster. OpenShift 4.5 is recommended. 
	* This lab does not provide OpenShift install instructions.
* `oc` command line tool
* `tkn` command line tool (optional)
* Text editor
* `git` and access to Github


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

``` yaml
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

Now that OpenShift Pipelines is installed, let's start building the pipeline by defining tasks.

## Defining Tasks

Tasks are the building blocks of your pipeline. A task executes one or many steps in sequence. It succeeds when all the steps finish successfully. Each task executes in a Pod while each step within that task is a container.

In OpenShift Pipelines you have two types of tasks: Cluster Tasks and Tasks. 

You can also download ready to use custom tasks from the [OpenShift catalogue](https://github.com/openshift/pipelines-catalog) or the [Tekton catalogue](https://github.com/tektoncd/catalog).

Let's start by checking Cluster Tasks:

### Cluster Tasks

A Cluster Task defines a task scoped for the entire cluster so any projects can use them. OpenShift Pipelines provides many Cluster Tasks ready to use. You can check them by running `oc get clustertasks`:

```
$ oc get clustertasks
NAME                       AGE
buildah                    3h41m
buildah-v0-11-3            3h41m
git-clone                  3h41m
jib-maven                  3h41m
kn                         3h41m
maven                      3h41m
openshift-client           3h41m
openshift-client-v0-11-3   3h41m
s2i                        3h41m
s2i-dotnet-3               3h41m
s2i-dotnet-3-v0-11-3       3h41m
s2i-go                     3h41m
s2i-go-v0-11-3             3h41m
s2i-java-11                3h41m
s2i-java-11-v0-11-3        3h41m
s2i-java-8                 3h41m
s2i-java-8-v0-11-3         3h41m
s2i-nodejs                 3h41m
s2i-nodejs-v0-11-3         3h41m
s2i-perl                   3h41m
s2i-perl-v0-11-3           3h41m
s2i-php                    3h41m
s2i-php-v0-11-3            3h41m
s2i-python-3               3h41m
s2i-python-3-v0-11-3       3h41m
s2i-ruby                   3h41m
s2i-ruby-v0-11-3           3h41m
s2i-v0-11-3                3h41m
tkn                        3h41m
```

For this lab, you'll use the `git-clone` Cluster Task when creating the pipeline as the first step, to clone the source code repository for the `hellogo` application. Verify details about this task using `oc describe clustertask git-clone`:

```
$ oc describe clustertask git-clone
Name:         git-clone
Namespace:    
Labels:       operator.tekton.dev/provider-type=community
Annotations:  manifestival: new
API Version:  tekton.dev/v1beta1
Kind:         ClusterTask
.... TRUNCATED ....
```

Next, let's create a few custom tasks.

### Custom Tasks

Custom Tasks or simply Tasks are similar to Cluster Tasks however they're project scoped. You can define your own tasks to make OpenShift Pipelines execute actions that are required to complete your pipeline.

In this example, you'll define three custom tasks to execute unit tests, run a static analysis of the source code, and use the `oc` command line to deploy the application. You can find the Task definitions as `yaml` files under the `pipeline-tasks` sub-directory in this repository.

For example, the `go_test_task.yaml` task definition is this:

``` yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: go-unit-tests
spec:
  workspaces:
  - name: source
  steps:
    - name: download-dependencies
      image: docker.io/library/golang:latest
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        echo Downloading dependencies
        go mod download
    - name: execute-tests
      image: docker.io/library/golang:latest
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        echo Testing application
        go test -v
```

You can check the remaining tasks in their respective files: `go_static_analysis_task.yaml` and `apply_manifest_task.yaml`.

Now, add these tasks to your project using the `oc` command line tool:

```
$ oc project cicd
$ oc apply -f pipeline-tasks
task.tekton.dev/apply-manifests created
task.tekton.dev/go-static-check created
task.tekton.dev/go-unit-tests created
```

Verify the tasks have been added with `oc get`:

```
$ oc get tasks
NAME              AGE
apply-manifests   40s
go-static-check   40s
go-unit-tests     40s
```

Finally, let's use a task from the OpenShift catalogue.

### Catalog

OpenShift and Tekton provide some ready to use tasks in a free open source catalogue. To use these tasks, download their `yaml` definition and import them into your cluster using the `oc` command line tool.

For this lab, we'll use the task `s2i-go` from the OpenShift catalogue to build the container image for the `hellogo` application using S2i. First, download it using `curl`:

```
$ curl -sO https://raw.githubusercontent.com/openshift/pipelines-catalog/master/task/s2i-go/0.1/s2i-go.yaml
```

Then, import it to the project using `oc`:

```
$ oc apply -f catalog-tasks/s2i-go.yaml
task.tekton.dev/s2i-go created
```

***Note***: OpenShift pipeline provides a Cluster Task `s2i-go` that also uses S2i to build Go application images. However, this task uses the concepts of Pipeline Resources that has some limitations. Instead of Pipeline Resources we're using the concept of a "workspace" to share data between tasks, therefore we need to import a task that uses workspaces instead. The Tekton project recommends avoiding using Resources as it may change or be deprecated in the future. For details check [Why Aren't PipelineResources in Beta?](https://github.com/tektoncd/pipeline/blob/master/docs/resources.md#why-arent-pipelineresources-in-beta) in Tekton's repository.


## Creating the Pipeline

Now that you have defined all required tasks, let's create a Pipeline to define the tasks relationship in a logical order to build and deploy the application.

You can define Pipelines graphically through the Web UI by selecting and connecting Tasks or you can define them in `yaml` file. By defining the Pipeline in a file, you can version control it and re-use it in different cluster.

Let's take a look at the `hellogo-pipeline.yaml` definition:

``` yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: hellogo-test-build-deploydev
spec:
  params:
  - name: git-url
    type: string
    description: The git repository URL to clone from.
  - name: branch-name
    type: string
    description: The git branch to clone.
    default: master
  - name: image
    type: string
    default: 'image-registry.openshift-image-registry.svc:5000/cicd/hellogo:latest'
  workspaces:
  - name: shared
  tasks:
  - name: fetch-repository
    taskRef:
      name: git-clone
      kind: ClusterTask
    workspaces:
    - name: output
      workspace: shared
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.branch-name)
    - name: deleteExisting
      value: "true"
  - name: go-unit-tests
    retries: 3
    taskRef:
      kind: Task
      name: go-unit-tests
    workspaces:
    - name: source
      workspace: shared
    runAfter:
    - fetch-repository
  - name: go-static-check
    taskRef:
      kind: Task
      name: go-static-check
    workspaces:
    - name: source
      workspace: shared
    runAfter:
    - fetch-repository
  - name: build
    params:
    - name: PATH_CONTEXT
      value: .
    - name: TLSVERIFY
      value: "false"
    - name: IMAGE
      value: $(params.image)
    workspaces:
    - name: source
      workspace: shared
    runAfter:
    - go-unit-tests
    - go-static-check
    taskRef:
      kind: Task
      name: s2i-go
  - name: deploy-dev
    params:
    - name: manifest_dir
      value: k8s-manifests
    - name: namespace
      value: hellogo-dev
    workspaces:
    - name: source
      workspace: shared
    runAfter:
    - build
    taskRef:
      kind: Task
      name: apply-manifests
  - name: deploy-qa
    params:
    - name: manifest_dir
      value: k8s-manifests
    - name: namespace
      value: hellogo-qa
    workspaces:
    - name: source
      workspace: shared
    runAfter:
    - deploy-dev
    taskRef:
      kind: Task
      name: apply-manifests
```

In this pipeline, we're using the `params` specification to define three input parameters for the pipeline:

1. `git-url`: The URL of the Git repository containing the source code of the application to build.
2. `branch-name`: The branch name in the source repo to build.
3. `image`: The path to the container image that s2i generates.

You can use the value of these parameters as input for the required task parameters with the notation `$(params.<NAME>)`. For example, to use the `git-url` parameter, use `$(params.git-url)`.

We're also using the `workspaces` specification to define the name of the workspace that the pipeline uses to share data between the different tasks. Later we'll define a Persistent Volume object and assign it as the workspace for this pipeline.

Finally, define the relationship between tasks by using the spec `runAfter` providing a list of tasks that need to execute before  each task. The initial task in the pipeline does not have this specification.

Now, import the pipeline into your project using the `oc` command line:

```
$ oc apply -f hellogo-pipeline.yaml
pipeline.tekton.dev/hellogo-test-build-deploydev created
```

You can see this pipeline by running `oc get pipelines` or through the Web UI:

![pipeline-webui](/pictures/pipeline-webui.png)


