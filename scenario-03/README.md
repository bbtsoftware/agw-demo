# Scenario 03 - Instructions

![Overview](./scenario-03.png)

## Description

This instruction descripes the steps needed to setup the azure
infrastructure for the current scenario.

## Disclaimer

This scenario was taken from the Microsoft Learn Quickstart guide for azure application gateway. See:

* https://learn.microsoft.com/en-us/azure/application-gateway/quick-create-portal
* https://learn.microsoft.com/en-us/azure/application-gateway/quick-create-bicep

## Prerequirement

The scripts shown require the [azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
as well as the [Bicep tools](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install).

Login to your azure portal and set the correct subscription.
In this example the subscription is called `MMA VS Prof. Subscription`. Use
the name of your subscription if you want to use the script.

```powershell
$sub = "MMA VS Prof. Subscription"
az login
az account set -s $sub
```

## Setup services

```powershell
$rg = "agw-demo-03-rg"
$file = "scenario-03.bicep"

az group create -n $rg -l northeurope
az deployment group create --name Scenario03 --resource-group $rg --template-file $file
```

* The url of the AGW (for north europe): https://agw-demo-03.northeurope.cloudapp.azure.com

## Cleanup

```powershell
az group delete -n $rg
```