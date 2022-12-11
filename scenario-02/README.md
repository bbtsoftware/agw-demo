# Scenario 02 - Instructions

![Overview](./scenario-02.svg)

## Description

This instruction descripes the steps needed to setup the azure
infrastructure for the current scenario.

## Key Points

The following key points are necessary to consider:

* For advanced routing features you need the application gateway SKU `Standard_v2` or `WAF_v2`
* Enable the service endpoints `Microsoft.Web` in the subnet of the application gateway
  for accessing the web app, when access restriction is enabled
* For HTTPS capabilities you need to upload a certificate containing the entire certificate chain to the application
  gateway
* For the application gateway to route traffic the backend health status needs to be `Healthy`
* When configuring the backend settings of the application gateway, use the following settings:
  * Override with new host name: `Yes`
  * Host name override: `Pick host name from backend target`

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

## Generate certificates

Generate the certificates needed for the TSL/SSL connection and puts them in the `cert` folder.
It is recommended to recreate the certificates for a new setup.

> NOTE: This command requires elevated privileges!

```powershell
..\scripts\generate-cert.ps1 -frontendDnsName agw-demo-02.northeurope.cloudapp.azure.com
```

## Setup services

```powershell
$rg = "agw-demo-02-rg"
$file = "scenario-02.bicep"
$webshopName = "webshop-agw-demo-02"

az group create -n $rg -l northeurope
az deployment group create --name Scenario02 --resource-group $rg --template-file $file --parameters webshopName=$webshopName
```

* The generated web app url: https://webshop-agw-demo-03.azurewebsites.net
* The url of the AGW (for north europe): https://agw-demo-02.northeurope.cloudapp.azure.com

## Deploy application

```powershell
az webapp deploy --resource-group $rg --name $webshopName --src-path '../.deployables/eShopOnWeb.zip' --type zip
```

## Cleanup

```powershell
az group delete -n $rg
```