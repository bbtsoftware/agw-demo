$sub = "MMA VS Prof. Subscription"
$rg = "agw-demo-04-rg"
$file = "scenario-04.bicep"
$webshopName = "webshop-agw-demo-04"

az login
az account set -s $sub
az group create -n $rg -l northeurope
az deployment group create --name Scenario04 --resource-group $rg --template-file $file --parameters webshopName=$webshopName
az webapp deploy --resource-group $rg --name $webshopName --src-path '../.deployables/eShopOnWeb.zip' --type zip
