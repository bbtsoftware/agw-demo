#$sub = "MMA VS Prof. Subscription"
#az login
#az account set -s $sub

$rg = "agw-demo-05-rg"
$file = "scenario-05.bicep"
$agwName = "agw-demo-05"
$webshopName = "webshop-agw-demo-05"
$webappName = "app-agw-demo-05"
$logName = "law-agw-demo-05"

az group create -n $rg -l northeurope
az deployment group create --name Scenario05 --resource-group $rg --template-file $file --parameters agwName=$agwName webshopName=$webshopName webappName=$webappName lawName=$logName

# setting up the log settings
$agwId = az network application-gateway show --query 'id' --name $agwName --resource-group $rg
$logId = az monitor log-analytics workspace show --query 'id' --workspace-name $logName --resource-group $rg

$accessLogSettings = '{\"category\":\"ApplicationGatewayAccessLog\",\"categoryGroup\":\"null\",\"enabled\":true,\"retentionPolicy\":{\"days\":0,\"enabled\":false}}'
$performanceLogSettings = '{\"category\":\"ApplicationGatewayPerformanceLog\",\"categoryGroup\":\"null\",\"enabled\":true,\"retentionPolicy\":{\"days\":0,\"enabled\":false}}'
$firewallLogSettings = '{\"category\":\"ApplicationGatewayFirewallLog\",\"categoryGroup\":\"null\",\"enabled\":true,\"retentionPolicy\":{\"days\":0,\"enabled\":false}}'
$logsSettings= "[$($accessLogSettings),$($performanceLogSettings),$($firewallLogSettings)]"
$metricsSettings= '[{\"category\":\"AllMetrics\",\"retentionPolicy\":{\"days\":0,\"enabled\":false},\"enabled\":true}]'

az monitor diagnostic-settings create --resource $agwId --name 'agw_diag_settings' --logs $logsSettings --metrics $metricsSettings --workspace $logId

az webapp deploy --resource-group $rg --name $webshopName --src-path '../.deployables/eShopOnWeb.zip' --type zip
az webapp deploy --resource-group $rg --name $webappName --src-path '../.deployables/AspNetCoreApp.zip' --type zip
