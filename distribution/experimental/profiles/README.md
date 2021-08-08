In this folder you will find a single example implementation of a Profile rollout, combined with various namespaced resources (such as MLFlow) managed as a single ArgoCD application for each Profile. In addition, the Profile is rolled out with the following:

```
  plugins:
  - kind: AwsIamForServiceAccount
    spec:
      awsIamRole: arn:aws:iam::123456789012:role/my-cluster-merge_profile_my-username
```

The IAM Role specified here will be attached to the default-editor ServiceAccount within the user's Namespace. This ServiceAccount is among other things uses by Notebook Servers and by Pipelines Components. Users can also elect to attach it when rolling out a KFServing model. What this enables is the injection of a user's pre-existing IAM policies into his or her Namespace. So if the IAM role `arn:aws:iam::123456789012:role/my-cluster-merge_profile_my-username` allows a user access to certain S3 buckets, then that users will be able to access those buckets from their Notebook Server, or will be able to run Pipelines that read from / write to those buckets.


This should be used in combination with the following setting:

`<<__enable_registration_flow__>>="true"`

NOTE that this offered here as a rudiementary but nevertheless effective way to use ArgoCD as a sort of Profile Controller. We are however also looking at how this can be made more sophisticated by extending the default Profile Controller to allow the declaration of arbitrary resources that should made available on each namespace.
