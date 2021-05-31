# Introduction

This project offers a Kubeflow distribution that has the following characteristics:
- It follows a fully declarative, GitOps approach using [ArgoCD](https://argoproj.github.io/argo-cd/). No other middleware is injected. All manifests are defined either as vanilla Kubernetes YAML specs, Kustomize specs, or Helm charts.
- Maximum integration with AWS managed services. We offload as much as possible to AWS, including database and artifact storage, identity management, load balancing, network routing and more! See below for a full listing of the currently supported AWS managed services
- A very simple [init script](./setup_repo.sh) and accompanying [config file](./examples/setup.conf). We have intentionally kept this a simple "find-and-replace" script (in favour using using a stricter approach, such as encoding the entire distribution as a Helm chart) in order to make the repo easy to extend.
- Currently we offer "Kubeflow 1.3", but with a few differences. We do not in all places follow the official [Kubeflow manifests](https://github.com/kubeflow/manifests), preferring instead to follow directly the (often much more recent) upstream distributions for both the core Kubeflow components (such as Pipelines, KFServing etc.) and free-standing applications (such as Istio, Certificate Manager, KNative etc.). As of the time of writing this, the difference is small, but over time (and until Kubeflow cuts its 1.4 release) it will become more significant.
- One particular area where we have chosen a fundamentally different approach relates to authentication and authorization. We have replaced the [oidc-authservice](https://github.com/arrikto/oidc-authservice) entirely, preferring instead to use [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) due to its wide adoption and active user base.
- Lastly, our interpretation of Kubeflow is that of an open and configurable ecosystem that can be easily extended with other services. As such, we also offer optional integrations with applications that are not part of the official Kubeflow distribution (such as [MLFlow](https://github.com/mlflow/mlflow) for example)



# AWS Integrations

This distribution assumes that you will be making use of the following AWS services:
- An [EKS](https://aws.amazon.com/eks/) Kubernetes cluster
- [Autoscaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/AutoScalingGroup.html) as Worker Nodes in the EKS cluster. We use the [cluster-autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) application to automatically scales nodes up or down depening on usage.
- An [RDS](https://aws.amazon.com/rds/) instance, with security group and VPC configuration that allows it to be accessed from the Worker Nodes in the EKS cluster. We authenticate to the RDS database using classical username / password credentials.
- [S3](https://aws.amazon.com/s3/) Bucket(s) for Pipeline and (optionally) MLFlow artifact storage.
- An [Elasticache](https://aws.amazon.com/elasticache/) Redis instance for storing cookies during the OIDC authentication process.
- A [Network Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html) via external ingress/egress is facilitated. We use the [aws-load-balancer-controller](https://github.com/kubernetes-sigs/aws-load-balancer-controller) application in order to automatically provision NLB's in the correct subnets.
- [Route53](https://aws.amazon.com/route53/) for DNS routing. We use the [external-dns](https://github.com/kubernetes-sigs/external-dns) application to automatically create records sets in Route53 in order to route from a public DNS to the NLB endpoint, as well as a [LetsEncrypt](https://letsencrypt.org/) DNS-01 solver to certify the domain with Route53.
- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) for storing sensitive data, such as various types of credentials. We use the [external-secrets](https://github.com/external-secrets/kubernetes-external-secrets) application to fetch these secrets into the Kubernetes cluster, allowing us to define in Git only the location where the secrets are to be found, as well as the ServiceAccount to use in order to find them.
- [IAM Roles for Service Accounts (IRSA)](https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/) to define the IAM Roles that may be assumed by specific Pods, by attaching a specific ServiceAccount to them. For example, we attach to the `external-dns` Pod a ServiceAccount that uses an IAM Role allowing certain actions in Route53. See the section below for a detailed listing of IRSA policies that are needed.
- [IAM Users](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html). As far as possible, we try to avoid relying on IAM Users with static credentials, but there are certain cases where IRSA is currently not supported by the underlying Kubeflow applications. This includes Kubeflow Pipelines (for S3 artifact storage) and KFServing (for serving models directly from S3).

In the future we may develop overlays that would make some of these services optional, but for the current release if you wish to take them out this needs to be done after forking the repo.


# AWS IAM Roles for Service Acocunts

Below you will find all of the IAM Policies that need to be attached to the IRSA roles. Before looking at the policies though, please take note of the fact that IRSA works via setting up a Trust relationship to a *specific* ServiceAccount in a *specific* Namespace. If you find that an IAM role is not being correctly assumed, it probably means that you are attaching it to a ServiceAccount that hasn't explicitly been authorized to do so.

## Trust Relationships

Let's take the [external-dns](https://github.com/kubernetes-sigs/external-dns) service as an example. The ServiceAccount for this application is defined [here](distribution/external-dns/serviceaccount.yaml), is named `external-dns` and is rolled out in the `kube-system` Namespace. To allow this ServiceAccount to assume an IAM Role, we have to set a [trust relationship](https://aws.amazon.com/blogs/security/how-to-use-trust-policies-with-iam-roles/) that looks as follows:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/SOMEUNIQUEID1234567890"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-central-1.amazonaws.com/id/SOMEUNIQUEID1234567890:sub": "system:serviceaccount:kube-system:external-dns"
        }
      }
    }
  ]
}
```

For every IRSA Role you set up, you will need the trust relationship above substituting for the actual oidc provider url as well as the the values "kube-system" and "external-dns" in `system:serviceaccount:kube-system:external-dns` for appropriate values.


## Policies

Further down in this guide we explain how to initialise this repository. For now, just take note that we use placeholder values such as `<<__role_arn.external_dns__>>` that will be replaced by the actual ARNs of the Roles you wish to use. Below is a listing of all of the IRSA roles in use in this repository, along with links to JSON files with example policies. If you do a search on the whole "distribution" folder you find exactly where these placeholders are used.

---
### `aws-loadbalancer-controller`

Needs policies that allows it to schedule a NLB in specific subnests.

- Placeholder:      `<<__role_arn.loadbalancer_controller__>>`
- Example ARN:      `arn:aws:iam::123456789012:role/my-cluster_kube-system_aws-loadbalancer-controller`
- Policy:           [link](./docs/iam_policies/aws-loadbalancer-controller.json)
---
### `cluster-autoscaler`

Needs policies that allows it to automatically scale EC2 instances up/down.

- Placeholder:      `<<__role_arn.cluster_autoscaler__>>`
- Example ARN:      `arn:aws:iam::123456789012:role/my-cluster_kube-system_aws-cluster-autoscaler`
- Policy:           [link](./docs/iam_policies/aws-cluster-autoscaler.json)


---
### `external-dns`

Needs policies that allows it to automatically create record sets in Route53.

- Placeholder:      `<<__role_arn.external_dns__>>`
- Example ARN:      `arn:aws:iam::123456789012:role/my-cluster_kube-system_external-dns`
- Policy:           [link](./docs/iam_policies/external-dns.json)

---
### `certificate-manager`

Needs policies that allows it to automatically create entries in Route53 in order to allow for DNS-01 solving.

- Placeholder:      `<<__role_arn.cert_manager__>>`
- Example ARN:      `arn:aws:iam::123456789012:role/my-cluster_cert-manager_cert-manager`
- Policy:           [link](./docs/iam_policies/cert-manager.json)


---
### `external-secrets`

The external-secrets application is middleman that will create ExternalSecret custom resources in specific namespaces. It can be configured in two ways.

Option 1: Allow the external-secret application wide authority to read and write AWS secrets

Option 2: Allow the external-secret application to assume roles that have more narrowly defined 

- Placeholder:        `<<__role_arn.external_secrets>>`
- Example ARN:        `arn:aws:iam::123456789012:role/my-cluster_kube-system_external_secrets`
- Policy:             
  - [Option 1](./docs/iam_policies/external-secrets.json)
  - Option 2 requires only a trust relationship. See below

In the second case, you then need to define roles to be assumed by the ExternalSecret resources that will be created. Each of these roles will need to have the follow trust relationship to the external-secrets role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/dev-kf13-14_kube-system_external-secrets"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

In addition, we need to grant each role limited access to secrets. We have chosen an approach of limiting access to secrets by namespace, but it is possible to make this more granular if desired. 

#### `ExternalSecret` for the `argocd` namespace

- Placeholder:        `<<__role_arn.external_secrets.argocd__>>=`
- Example ARN:        `arn:aws:iam::123456789012:role/my-cluster_argocd`
- Policy:             [link](./docs/iam_policies/external-secrets_argocd.json)


#### `ExternalSecret` for the `kubeflow` namespace

- Placeholder:        `<<__role_arn.external_secrets.kubeflow__>>=`
- Example ARN:        `arn:aws:iam::123456789012:role/my-cluster_kubeflow`
- Policy:             [link](./docs/iam_policies/external-secrets_kubeflow.json)


#### `ExternalSecret` for the `oauth2_proxy` namespace

- Placeholder:        `<<__role_arn.external_secrets.oauth2_proxy__>>=`
- Example ARN:        `arn:aws:iam::123456789012:role/my-cluster_oauth2_proxy`
- Policy:             [link](./docs/iam_policies/external-secrets_oauth2_proxy`.json)


#### `ExternalSecret` for the `mlflow` namespace

- Placeholder:        `<<__role_arn.external_secrets.mlflow__>>=`
- Example ARN:        `arn:aws:iam::123456789012:role/my-cluster_mlflow`
- Policy:             [link](./docs/iam_policies/external-secrets_mlflow.json)


---
# Deployment

This repository contains Kustomize manifests that point to the upstream
manifest of each Kubeflow component and provides an easy way for people
to change their deployment according to their need. ArgoCD application
manifests for each componenet will be used to deploy Kubeflow. The intended
usage is for people to fork this repository, make their desired kustomizations,
run a script to change the ArgoCD application specs to point to their fork
of this repository, and finally apply a master ArgoCD application that will
deploy all other applications.

## Prerequisites

- kubectl (latest)
- kustomize 4.0.5


## The `setup.conf` file and `setup_repo.sh` script

This repository uses a very simple initialisation script, [./setup_repo.sh ](./setup_repo.sh) that takes an config file such as the example one, [./examples/setup.conf](./examples/setup.conf) and iterates over all lines therein. A single line would for example look as follows:
```bash
<<__role_arn.cluster_autoscaler__>>=arn:aws:iam::123456789012:role/my-cluster_kube-system_aws-cluster-autoscaler
```
The init script will look for all occurences in the ./distribution folder of the placeholder `<<__role_arn.cluster_autoscaler__>>` and will replace it with the value `arn:aws:iam::123456789012:role/my-cluster_kube-system_aws-cluster-autoscaler`. Please note that that comments (`//`, `#`), quatation marks (`"`, `'`) or unnecessary line-breaks should be avoided.

You may add any additional placeholder/value pairs you want. The naming convention `<<__...__>> ` has no functional purpose other than to aid readability and minimise the risk of a "find-and-replace" being performed on a value that was not meant as a placeholder.




## Deployment steps

To initialise your repository, do the following:
- fork this repo
- modify the kustomizations for your purpose. You may in particular wish to edit `distribution/kubeflow.yaml` with the selection of applications you wish to roll out
- set up a "setup.conf" file (or do a manual "find-and-replace" if you prefer) such as [this](./examples/setup.conf) one in the root of the repository
- run `./setup_repo.sh setup.conf`
- commit and push your changes

Start up external-secret and argocd:

```bash
kustomize build distribution/external-secrets/ | kubectl apply -f -
kustomize build distribution/argocd/ | kubectl apply -f -
```

Finally, roll out kubeflow with:
```bash
kubectl apply -f distribution/kubeflow.yaml
```

If you wish, you may also set up ArgoCD to manage itself, as follows:

```bash
kubectl apply -f distribution/argocd-applications/argocd.yaml
```

## Customizing the Jupyter Web App

To customize the list of images presented in the Jupyter Web App
and other related setting such as allowing custom images,
edit the [spawner_ui_config.yaml](./distibution/kubeflow/notebooks/jupyter-web-app/spawner_ui_config.yaml)
file.


## Bonus: Extending the Volumes Web App with a File Browser

A large problem for many people is how to easily upload or download data to and from the
PVCs mounted as their workspace volumes for Notebook Servers. To make this easier
a simple PVCViewer Controller was created (a slightly modified version of
the tensorboard-controller). This feature was not ready in time for 1.3,
and thus I am only documenting it here as an experimental feature as I believe
many people would like to have this functionality. The images are grabbed from my
personal dockerhub profile, but I can provide instructions for people that would
like to build the images themselves. Also, it is important to note that
the PVC Viewer will work with ReadWriteOnce PVCs, even when they are mounted
to an active Notebook Server.

Here is an example of the PVC Viewer in action:

![PVCViewer in action](./docs/images/vwa-pvcviewer-demo.gif)

To use the PVCViewer Controller, it must be deployed along with an updated version
of the Volumes Web App. To do so, deploy
[experimental-pvcviewer-controller.yaml](./distibution/argocd-applications/experimental-pvcviewer-controller.yaml) and
[experimental-volumes-web-app.yaml](./distibution/argocd-application/experimental-volumes-web-app.yaml)
instead of the regular Volumes Web App. If you are deploying Kubeflow with
the [kubeflow.yaml](./distribution/kubeflow.yaml) file, you can edit the root
[kustomization.yaml](./distibution/kustomization.yaml) and comment out the regular
Volumes Web App and uncomment the PVCViewer Controller and Experimental
Volumes Web App.

### Updating the deployment

By default, all the ArgoCD application specs included here are
setup to automatically sync with the specified repoURL.
If you would like to change something about your deployment,
simply make the change, commit it and push it to your fork
of this repo. ArgoCD will automatically detect the changes
and update the necessary resources in your cluster.


# Accessing the ArgoCD UI

By default the ArgoCD UI is rolled out behind a ClusterIP. This can be accessed for development purposes with port forwarding, for example:

```bash
kubectl port-forward svc/argocd-server -n argocd 8888:80
```

The UI will now be accessible at `localhost:8888` and can be accessed with the initial admin password. The password is stored in a secret and can be read as follows:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

If you wish to update the password, this can be done using the [argcd cli](https://github.com/argoproj/argo-cd/releases/latest), using the following commands:
```bash
argocd login localhost:8888
argocd account update-password
```

