# Continuous Delivery with containers to Kubernetes using Visual Studio Team Services


## Table of Contents



## Overview and Pre-Requisites

### Overview

In this lab, you're going to take a Node.js application that is composed of 2 Docker containers and publish it using CI/CD practices to Kubernetes cluster running on Azure Container Service, leveraging Visual Studio Team Services. The Docker images you create will be pushed to an instance of Azure Container Registry.

The 2 container components of this lab are:
1. colorapp
2. colormicroservice

Essentially, the **colorapp** does AJAX requests to the **colormicroservice** and plots the results. The **colormicroservice** returns the hostname of the machine in addition to a random hex color.

### Pre-requisites

- Docker installed on your machine
    
    On Windows, install Docker for Windows: https://docs.docker.com/docker-for-windows/install/#install-docker-for-windows 
    
    On a Mac, install Docker for Mac: https://docs.docker.com/docker-for-mac/install/#install-and-run-docker-for-mac 
    
    Then, verify installation:
    ```
    docker -v
    ```
- Visual Studio Code (or your favorite code editor)
    
    On Windows and Mac, download and install from: https://code.visualstudio.com/Download

- Azure CLI installed and configured with your Azure subscription
    
    On Windows, download and install from: https://aka.ms/InstallAzureCliWindows 
    On a Mac, run the below command in Terminal
    ```
    curl -L https://aka.ms/InstallAzureCli | bash
    ```

    Then login into your Azure subscription to verify installation:
    ```
    az login
    ```

    If you have many subscriptions, you may choose one:
    ```
    az account set -s <subscription-GUID>
    ```

    Create the Resource Group to use throughout the lab:
    ```
    az group create -n <rg name> -l westeurope 
    ```

    Set the default Resource Group for your session, to avoid typing it in all commands
    ```
    az configure --defaults group=<rg name>
    ```
- You should also **Fork** this repository as one of the steps would involve you modifying the source code and committing it to trigger the CI/CD pipeline.
 
### Topics Covered

- Running locally
- Pushing Docker images to Azure Container Registry
- Creating Azure Container Service with Kubernetes as the orchestrator
- Creating staging deployment slot for microservice
- Configure Build Pipeline
- Configure Release Pipeline
- Triggering a build using a code change
- Scaling the application

## Lab


### Running locally

**Fork** then clone your forked repository to your machine

Change directory to ```ApplicationModernization/Modules/CICDKubernetesVSTS```

Build both images
```
docker build -t colorapp src/colorapp/.
docker build -t colormicroservice src/colormicroservice/.
```

Run using Docker Compose
```
docker-compose up
```

Browse to http://localhost/
![Colors of the cluster app running locally](media/colorapplocal.png)

### Pushing Docker images to Azure Container Registry

Create an Azure Container Registry (~2 minutes)
```
az acr create -n <registry name> --admin-enabled --sku Managed_Standard
```

Login into the registry. This will enable your local Docker installation to be able to access the registry.
```
az acr login -n <registry name>
```

Change both image tags to point to the registry
```
docker tag colorapp:latest <registry name>.azurecr.io/<image>:latest
docker tag colormicroservice:latest <registry name>.azurecr.io/<image>:latest
```

Publish your images to the registry
```
docker push <registry name>.azurecr.io/colorapp:latest
docker push <registry name>.azurecr.io/colormicroservice:latest
```

### Creating Azure Container Service with Kubernetes as the orchestrator

Create the ACS cluster with Kubernetes as the orchestrator (~ 10 mins)
```
az acs create -n <acs name> -t kubernetes --generate-ssh-keys
```

Install ```kubectl```. On Windows, add ```C:\Program Files (x86)\``` to your **PATH** then restart the CMD prompt

```
az acs kubernetes install-cli
```

Get the cluster credentials
```
az acs kubernetes get-credentials -n <acs name>
```

### Create Kubernetes namespaces for production and staging

Examine the ```k8sconfig/namespaces.yaml``` file. This defines the [Kubernetes namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) for the production and staging environments. Once created, you should be able to target a specific environment while deploying your containers.

```YAML
apiVersion: v1
kind: Namespace
metadata:
  name: production
---
apiVersion: v1
kind: Namespace
metadata:
  name: staging
```

Execute the configuration by running
```
kubectl apply -f k8sconfig/namespaces.yaml
```

Browse to the Kubernetes dashboard
```
az acs kubernetes browse -n  <acs name>
```

You should be able to view the Kubernetes dashboard running as in the following screenshot.

![Kubernetes dashboard](media/k8sui.png)


Examine the ```k8sconfig/colorapp.yaml``` and ```k8sconfig/colormicroservice.yaml``` files which should be like the below. Notice the placeholders ```ACRNAME```, ```BUILDVERSION``` and ```COLORMICROSERVICEENV```. These will be replaced by the build process in VSTS with the variables defined inside VSTS.

> Note the ```imagePullSecrets``` property. When you configure the build steps on VSTS, you'll configure a secret on Kubernetes with the Docker repository credentials. This tells Kubernetes what is the name of the secret you configured to allow it to pull the image from your Azure Container Registry.


```YAML
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: colorapp
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: colorapp
    spec:
      containers:
      - name: colorapp
        image: ACRNAME.azurecr.io/colorapp:BUILDVERSION
        ports:
        - containerPort: 3000
        env:
        - name: COLORMICROSERVICE
          value: "COLORMICROSERVICEENV"
      imagePullSecrets:
        - name: ACRNAME
---
apiVersion: v1
kind: Service
metadata:
  name: colorapp
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 3000
      protocol: TCP
  selector:
    app: colorapp
```

```YAML
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: colormicroservice
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: colormicroservice
    spec:
      containers:
      - name: colormicroservice
        image: ACRNAME.azurecr.io/colormicroservice:BUILDVERSION
        ports:
        - containerPort: 3000
      imagePullSecrets:
        - name: ACRNAME
---
apiVersion: v1
kind: Service
metadata:
  name: colormicroservice
spec:
  type: LoadBalancer
  ports:
    - port: 3000
      targetPort: 3000
      protocol: TCP
  selector:
    app: colorapp
```


### Configure Build Pipeline

You're now going to use Visual Studio Team Services to setup the Build and Release pipelines.

Go to http://www.visualstudio.com and hit **Sign in** then sign in with your Microsoft account you use for Azure.

![Sign-in to Visual Studio Team Services](media/vstssignin.png)

If you don't have an account, setup an account by hitting **Create new account** otherwise, just create a **new team project**.

![Create an account or project](media/vstsselectproject.png)

Create an account if you have to. This should take a few minutes, and it will create a project for you.

![Create an account if you have to](media/vstscreateaccount.png)

Otherwise, create a new project on your existing account.

![Create a project](media/vstscreateproject.png) 

Once your project is ready, you will see the screen below. Since you're already hosting the source code somewhere else (you forked this repo in Github, right?), you'll choose the option to build code from an external repository.

![Build from external repository](media/vstsbuildcodeexternal.png)

Hit the **New Definition** button to start.

![Create new build definition](media/newbuilddef.png)

Select the **empty process** template.

![Select Empty process template](media/createbuilddef.png)

Change the process agent queue to **Hosted Linux Preview**. This has the tools required to build the Docker images.

![Change build agent to Hosted Linux](media/process.png)

Now authorize Visual Studio Team Services to your Github account then pick the right repository that you forked.

![Configure sources](media/getsources.png)

After configuring the repository, hit **Add Task**. You're now going to add a Docker task to build a Docker image from your source code.

![Add Docker task](media/adddockertask.png)

In the task, you're going to point it towards your Azure Container Registry and you're going to configure it to point to the Docker file that should be in the following path in your forked repository: ```ApplicationModernization/Modules/CICDKubernetesVSTS/src/colormicroservice/Dockerfile```

Additionally, make sure that the image name is ```colormicroservice:$(Build.BuildId)``` and that **Qualify Image Name** is checked.

This will tag the image version with your Azure Container Registry name and **Build Id** allowing you to control which version is eventually deployed. Do not use the **latest** tag here.

![Build image task](media/buildtask.png)

Now add another Docker task, this time configure it with **Push an image** action and the same image name ```colormicroservice:$(Build.BuildId)```. Make sure **Qualify Image Name** is checked.

![Push image task](media/pushtask.png)

Head over to the **Triggers** tab, and enable Continuous Integration. This will trigger the build pipeline whenever a new change is committed to your code repository.

Naturally, you could do this on a specific branch.

![Enable CI](media/buildtrigger.png)

Finally, hit the **Save & queue** button to queue a build manually, then review the build log, you should be able to see something like the below.

![Build log](media/buildlog.png)

Congratulations, you've run your first build pipeline! If you login to the Azure Portal and navigate to your Azure Container Registry, you should be able to find the image there.

Your tag here may differ depending on how many times you ran this build. Every time the build runs, a new image with a new tag is created.

![Azure Container Registry](media/acr.png)


### Configure Release Pipeline for Staging

Now that you have your build pipeline configured to trigger automatically on every code commit, it is time for you to configure the release pipeline, to actually deploy your new Docker images.

Head over to the **Releases** tab and hit the **new definition** button. 

![Create Release definition](media/newreleasedef.png)

Select the **empty process** template.

![Select the Empty process template](media/releaseempty.png)

And name this environment **Staging** then click on the **1 phase, 0 task** link to start adding tasks.

![Name it Staging](media/createstaging.png)

Now add an **Azure App Service Deploy** task.

![Add App Service Deploy task](media/addappservicedeploytask.png)

Configure the task by choosing your microservice Web App, checking **Deploy to slot** and choosing the **staging slot**.

You also need to provide your Azure Container Registry namespace in the form of ``<acr name>.azurecr.io``, the microservice image name in the repository as ``colormicroservice`` and the image tag as ``$(Build.BuildId)``.

![Configure the task](media/configureappservicedeploytask.png)

When you're done, save the definition and head to the **Pipeline** tab and click on **add artifact**.

![Add artifact to pipeline](media/pipelineaddartifact.png)

Then configure the artifact version to be specified at the time of release, and give it a name **Drop**.

![Configure artifact](media/configureartifact.png)

Finally, hit the small lightning bolt on the artifact to configure the continuous deployment trigger then hit save.

![Configure Continuous Delivery](media/artifactcd.png)

At this point, you may check your configuration by manually triggering a release through hitting the **Release** button then select the latest version from the Drop dropdown list.

![Manual release](media/manualrelease.png)

Review the logs to see the release progress.

![Manual release logs](media/manualreleaselog.png)

Once the release is complete, you should be able to access the microservice in the staging environment here [http://<microservice name\>-staging.azurewebsites.net/colors]()

![Microservice staging output](media/microservicestaging.png)

### Add Production environment to Release Pipeline

You'll now create a new environment, pointing to the production slot on the Web App.

Hover over the **Staging** environment and hit the **add** button to add a serial release step

![Add Production environment](media/addproductionenv.png)

Like before, select the **empty process** template.

![Select the Empty process template](media/releaseempty2.png)

And name this environment **Production** then click on the **1 phase, 0 task** link to start adding tasks.

![Name it Production](media/createproduction.png)

Now add an **Azure App Service Manage** task.

![Add App Service Deploy task](media/addappservicemanagetask.png)

Configure the task with the microservice Web App name and choose the slot and make sure **Swap with production** is checked then **save**.

![Configure the task](media/configureappservicemanagetask.png)

Go back to the **Pipeline** tab and click on the **Pre-deployment conditions** to configure a gated deployment step.

![Pre-deployment conditions](media/predeployment.png)

Add yourself (or someone else on your project) as a pre-deployment approver. This means that you will need to approve swapping the staging environment into production.

![Pre-deployment approver](media/predeploymentapprover.png)

### Adding color into this

Now as you may have noticed, when you browse to the Web App [http://<color app name\>.azurewebsites.net](http://webappname.azurewebsites.net), despite this app being called "colors" of the cluster, there aren't actually any colors!

![Color app running](media/colorapponazure.png)

We'll go ahead and fix that now.

Go to your fork of the Github repository, and navigate to ```ApplicationModernization/CICDAppServiceVSTS/src/colormicroservice/routes/colors.js``` then hit the edit button to edit this file.

![color.js](media/colorjs.png)

Comment line 9 and uncomment line 10, to enable colors.

![Edit color.js](media/colorjsedit.png)

Scroll down to the bottom, and hit **Commit changes**.

![Commit changes](media/commitchanges.png)

This should trigger a build, then release the change to the staging environment. You will also get an email now that you need to approve swapping this deployment into production.

![Pre-approval email](media/preapprovalemail.png)

Once you click on the button, you will be able to Approve or Reject this. Hit Approve, and this will continue the deployment pipeline to deploy to production.

![Pre-approval email](media/preapprovalscreen.png)

Switch to the browser running the Web App, wait for a few minutes as the swap is completed, and you should start seeing some color.


![Color app running](media/colorapponazurecolor.png)

### Scaling your cluster
Now that you are running the new app, scale the App Service Plan to more instances either using the Azure Portal or by executing the command below.
```
az appservice plan update --number-of-workers 10 -n <plan name>
```

In a few moments, as the Docker images are being pulled and deployed on new VMs, you should see more instances lighting up on your screen.


![Color app running at scale](media/colorapponazurescale.png)

## Conclusion

In this lab, you created a private Docker image repository on Azure Container Registry and pushed an application image to it. You also created an App Service Plan running Linux and a Web App with production and staging slots.

You configured a CI/CD pipeline using Visual Studio Team Services to build Docker images and push them to Azure Container Registry, then deploy them to a staging slot, followed by swapping with production.

Finally, you scaled the App Service plan to run more instances.


## End your Lab

Clean up your lab by deleting the Resource Group you created.
```
az group delete -n <rg name>
```

## Additional Resources and References

- [Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-registry/)
- [Azure App Service Linux](https://docs.microsoft.com/en-us/azure/app-service/app-service-linux-readme)
- [Visual Studio Team Services](https://www.visualstudio.com/team-services/)
- [Continuous deployment with Azure Web Apps for Containers](https://docs.microsoft.com/en-us/azure/app-service/containers/app-service-linux-ci-cd)



## License

Copyright (c) Microsoft Corporation. All rights reserved.

Licensed under the [MIT](LICENSE) License.
