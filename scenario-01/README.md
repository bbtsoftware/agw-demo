# Scenario 01 - Instructions

![Overview](./scenario-01.png)

## Description

This instruction descripes the steps needed to setup the azure
infrastructure for the current scenario.

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
$rg = "agw-demo-01-rg"
$file = "scenario-01.bicep"
$webshopName = "webshop-agw-demo-01"

az group create -n $rg -l northeurope
az deployment group create --name Scenario01 --resource-group $rg --template-file $file --parameters webshopName=$webshopName
```

The generated web app url: https://webshop-agw-demo-01.azurewebsites.net

## Deploy application

```powershell
az webapp deploy --resource-group $rg --name $webshopName --src-path '../.deployables/eShopOnWeb.zip' --type zip
```

## Cleanup

```powershell
az group delete -n $rg
```