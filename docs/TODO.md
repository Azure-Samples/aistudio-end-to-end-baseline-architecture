# TODO items for OpenAI e2e baseline

- Add Bicep to deploy Runtime. Currently, the Bicep deploys a compute instance. This task will create the runtime that references the compute instance and allows for the testing of the flow in the UI.
- Build development story
  - Determine how to submit flow files for testing through the CLI. You might start by exporting an existing simple 'Echo' flow from the UI to local. Guidance here on submitting from local: [Guidance](https://learn.microsoft.com/en-us/azure/machine-learning/prompt-flow/how-to-integrate-with-llm-app-devops?view=azureml-api-2&tabs=cli#submitting-runs-to-the-cloud-from-local-repository).
  - Determine what development inner loop would look like
  - Determine logical steps for PR and CI might look like
- Determine the appropriate deployment environment
  - Currently, we are deploying via the UI to ML Compute - via UI. This does not support Availability Zones, auto scaling
  - Need to deploy to service that supports zonal redundancy, scaling, private networking - likely App Service or ACA. Introducing AKS will likely add too much complexity to the baseline.
  - Will need Private Endpoint to allow App Service Client to connect to Endpoint/Deployment
  - Need to ensure the deployed endpoint/deployment can access locked down required resources - OpenAI,Cog Search, etc
  - Need to deploy from CLI
- Ensure we have minimum role assignments required for Managed Identity for Azure ML Workspace in machinelearning.bicep. 
- Determine if we should create separate Managed Identity for Endpoint/Deployment than the one used for the authoring. If so, create and update RI.
- Add/update appropriate or missing NSGs in network.bicep
- Make the jumpbox/bastion deployment a parm 
