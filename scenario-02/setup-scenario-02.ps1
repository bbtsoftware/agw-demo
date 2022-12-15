#$sub = "MMA VS Prof. Subscription"
#az login
#az account set -s $sub

$rg = "agw-demo-02-rg"
$file = "scenario-02.bicep"
$webshopName = "webshop-agw-demo-02"

az group create -n $rg -l northeurope
az deployment group create --name Scenario02 --resource-group $rg --template-file $file --parameters webshopName=$webshopName
az webapp deploy --resource-group $rg --name $webshopName --src-path '../.deployables/eShopOnWeb.zip' --type zip