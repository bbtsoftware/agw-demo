// must be unique within azure
param webshopName string = 'webshop-agw-demo-01'
param sqlServerName string = 'sql-agw-demo-01'

param location string = resourceGroup().location

// source: https://rakesh-suryawanshi.medium.com/generate-random-password-in-azure-bicep-template-3411aba22fff
resource sqlAdminPasswordScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'password-generate'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '3.0' 
    retentionInterval: 'P1D'
    scriptContent: loadTextContent('../scripts/generate-pwd.ps1')
  }
}

//
// DATABASES
//
var sqlLogin = 'sqladmin'
var sqlPassword = sqlAdminPasswordScript.properties.outputs.password
resource sqlServer 'Microsoft.Sql/servers@2022-02-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlLogin
    administratorLoginPassword: sqlPassword
  }
}

// -------------------------------------------------
// CAUTION!! This setting is for demo purposes only
// -------------------------------------------------
// allow all connections from azure to the database server
resource sqlAllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2020-11-01-preview' = {
  name: 'AllowAllWindowsAzureIps'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource catalogDb 'Microsoft.Sql/servers/databases@2022-02-01-preview' = {
  parent: sqlServer
  name: 'sqldb-agw-demo-01-catalogdb'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    isLedgerOn: false
    zoneRedundant: false
  }
}

resource identityDb 'Microsoft.Sql/servers/databases@2022-02-01-preview' = {
  parent: sqlServer
  name: 'sqldb-agw-demo-01-identity'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    isLedgerOn: false
    zoneRedundant: false
  }
}


//
// WEB APPS
//
resource appServicePlan 'Microsoft.Web/serverFarms@2022-03-01' = {
  name: 'plan-demo-01'
  location: location
  sku: {
    tier: 'Free'
    name: 'F1'
  }
  kind: 'app'
}

var catalogConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${catalogDb.name};Persist Security Info=False;User ID=${sqlLogin};Password=${sqlPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var identityConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${identityDb.name};Persist Security Info=False;User ID=${sqlLogin};Password=${sqlPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

resource webShopApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webshopName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [{
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Development'
      }]
      connectionStrings: [{
        name: 'CatalogConnection'
        connectionString: catalogConnectionString
      }
      {
        name: 'IdentityConnection'
        connectionString: identityConnectionString
      }]
    }
  }
}

