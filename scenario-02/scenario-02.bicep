// must be unique within azure
param webshopName string = 'webshop-agw-demo-02'
param sqlServerName string = 'sql-agw-demo-02'

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
  name: 'sqldb-agw-demo-02-catalogdb'
  location: location
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

resource identityDb 'Microsoft.Sql/servers/databases@2022-02-01-preview' = {
  parent: sqlServer
  name: 'sqldb-agw-demo-02-identity'
  location: location
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}


//
// WEB APPS
//
resource appServicePlan 'Microsoft.Web/serverFarms@2022-03-01' = {
  name: 'plan-demo-02'
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

//
// AGW
//
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'vnet-agw-demo-02'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vnet-agw-demo-02-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: 'pip-agw-demo-02'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Dynamic'
  }
  sku: {
    name: 'Basic'
    tier: 'Regional'
  }
}

// webshop-agw-demo-02.azurewebsites.net
var webShopHostname = webShopApp.properties.defaultHostName

var agwName = 'agw-demo-02'
var frontePort80Name = 'port_80'
var frontendIpConfigName = 'appGwPublicFrontendIp'
var webshopBackendPoolName = 'webshop_backend_pool'
var httpListenerName = 'http_listener'
var redirectConfigName = 'redirectConfig_01'

resource agw 'Microsoft.Network/applicationGateways@2020-11-01' = {
  name: agwName
  location: location
  properties: {
    sku: {
      name: 'Standard_Small'
      tier: 'Standard'
      capacity: 1
    }
    gatewayIPConfigurations: [{
      name: 'appGatewayIpConfig'
      properties: {
        subnet: {
          id: vnet.properties.subnets[0].id
        }
      }
    }]
    frontendIPConfigurations: [{
      name: frontendIpConfigName
      properties: {
        publicIPAddress: {
          id: publicIp.id
        }
      }
    }]
    frontendPorts: [{
      name: frontePort80Name
      properties: {
        port: 80
      }
    }]
    httpListeners: [{
      name: httpListenerName
      properties: {
        frontendIPConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', agwName, frontendIpConfigName)
        }
        frontendPort: {
          id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', agwName, frontePort80Name)
        }
        protocol: 'Http'
      }
    }]
    backendAddressPools: [{
      name: webshopBackendPoolName
      properties: {
        backendAddresses: [{
          fqdn: webShopHostname
        }]
      }
    }]
    backendHttpSettingsCollection: [{
      name: 'http-backendsettings'
      properties: {
        port: 80
        protocol: 'Http'
      }
    }]
    redirectConfigurations: [{
      name: redirectConfigName
      properties: {
        redirectType: 'Permanent'
        targetUrl: 'http://${webShopHostname}'
        includePath: true
        includeQueryString: true
      }
    }]
    requestRoutingRules: [{
      name: 'rule-01'
      properties: {
        ruleType: 'Basic'
        httpListener: {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, httpListenerName)
        }
        redirectConfiguration: {
          id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', agwName, redirectConfigName)
        }
      }
    }]
  }
}

output webShopHostname string = webShopHostname
output agwPublicIp string = publicIp.properties.ipAddress
output agwPublicIpFqdn string = publicIp.properties.dnsSettings.fqdn
