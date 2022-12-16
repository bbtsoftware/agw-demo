#$sub = "MMA VS Prof. Subscription"
#az login
#az account set -s $sub

$rg = "agw-demo-04-rg"
# for demo purposes
$file = "scenario-04-demo.bicep"
$webshopName = "webshop-agw-demo-04"
$webappName = "app-agw-demo-04"

az group create -n $rg -l northeurope
az deployment group create --name Scenario04 --resource-group $rg --template-file $file --parameters webshopName=$webshopName webappName=$webappName

az webapp deploy --resource-group $rg --name $webshopName --src-path '../.deployables/eShopOnWeb.zip' --type zip
az webapp deploy --resource-group $rg --name $webappName --src-path '../.deployables/AspNetCoreApp.zip' --type zip

az webapp deploy --resource-group $rg --name "$($webshopName)-plain" --src-path '../.deployables/eShopOnWeb.zip' --type zip
az webapp deploy --resource-group $rg --name "$($webappName)-plain" --src-path '../.deployables/AspNetCoreApp.zip' --type zip