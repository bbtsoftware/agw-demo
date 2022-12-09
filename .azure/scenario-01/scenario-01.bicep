param webshopName string = 'webshop-agw-demo-01' // must be unique within azure
param appServicePlanName string = 'plan-demo-01'
param location string = resourceGroup().location

resource appServicePlan 'Microsoft.Web/serverFarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    tier: 'Free'
    name: 'F1'
  }
  kind: 'app'
}

resource webShopApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webshopName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
  }
}
