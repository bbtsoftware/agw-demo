// with additional plain web apps for demo purposes.

// must be unique within azure
param webshopName string = 'webshop-agw-demo-04'
param webappName string = 'app-agw-demo-04'
param sqlServerName string = 'sql-agw-demo-04'

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
  name: 'sqldb-agw-demo-04-catalogdb'
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
  name: 'sqldb-agw-demo-04-identity'
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
// Public IP
//
resource publicIp 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: 'pip-agw-demo-04'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'agw-demo-04'
    }
  }
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
}

//
// VNET for AGW
//
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'vnet-agw-demo-04'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vnet-agw-demo-04-subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          // required for the AGW to access the web app if access restriction is enabled
          serviceEndpoints: [{
            service: 'Microsoft.Web'
            locations: ['*']
          }]
        }
      }
    ]
  }
}
var agwSubnetId = vnet.properties.subnets[0].id

//
// WEB APPS
//
resource appServicePlan 'Microsoft.Web/serverFarms@2022-03-01' = {
  name: 'plan-demo-04'
  location: location
  sku: {
    tier: 'Free'
    name: 'F1'
  }
  kind: 'app'
}

resource appServicePlanPlain 'Microsoft.Web/serverFarms@2022-03-01' = {
  name: 'plan-demo-04-plain'
  location: location
  sku: {
    tier: 'Free'
    name: 'F1'
  }
  kind: 'app'
}

var catalogConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${catalogDb.name};Persist Security Info=False;User ID=${sqlLogin};Password=${sqlPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var identityConnectionString = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${identityDb.name};Persist Security Info=False;User ID=${sqlLogin};Password=${sqlPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

var onlyAgwIpSecRestriction = [
  {
      vnetSubnetResourceId: agwSubnetId
      action: 'Allow'
      priority: 1000
      name: 'allow_agw_income'
      description: 'Allows Traffic from the AGW Subnet'
  }
  {
      ipAddress: 'Any'
      action: 'Deny'
      priority: 2147483647
      name: 'Deny all'
      description: 'Deny all access'
  }
]

resource webShopAppPlain 'Microsoft.Web/sites@2022-03-01' = {
  name: '${webshopName}-plain'
  location: location
  properties: {
    serverFarmId: appServicePlanPlain.id
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

resource aspWebAppPlain 'Microsoft.Web/sites@2022-03-01' = {
  name: '${webappName}-plain'
  location: location
  properties: {
    serverFarmId: appServicePlanPlain.id
    siteConfig: {
      appSettings: [{
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }]
    }
  }
}

resource webShopApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webshopName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [{
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }
      {
        // used for the images loaded from the database
        name: 'CatalogBaseUrl'
        value: '/shop/'
      }]
      connectionStrings: [{
        name: 'CatalogConnection'
        connectionString: catalogConnectionString
      }
      {
        name: 'IdentityConnection'
        connectionString: identityConnectionString
      }]
      ipSecurityRestrictions: onlyAgwIpSecRestriction
      virtualApplications: [
        {
          virtualPath: '/'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: false
        }
        {
          virtualPath: '/shop'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: false
        }
      ]
    }
  }
}

resource aspWebApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webappName
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [{
        name: 'ASPNETCORE_ENVIRONMENT'
        value: 'Development'
      }]
      ipSecurityRestrictions: onlyAgwIpSecRestriction
      virtualApplications: [
        {
          virtualPath: '/'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: false
        }
        {
          virtualPath: '/app'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: false
        }
      ]
    }
  }
}

//
// AGW
//
// webshop-agw-demo-04.azurewebsites.net
var webShopHostname = webShopApp.properties.defaultHostName
var webAppHostname = aspWebApp.properties.defaultHostName

var agwName = 'agw-demo-04'
resource agw 'Microsoft.Network/applicationGateways@2020-11-01' = {
  name: agwName
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    gatewayIPConfigurations: [{
      name: 'appGatewayIpConfig'
      properties: {
        subnet: {
          id: agwSubnetId
        }
      }
    }]
    sslCertificates: [{
      name: 'ssl_cert'
      // use the `generate-cert.ps1` script to generate new certificates!
      properties: {
        data: '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'
        password: 'RhvFyl3p@z*b7r*3A'
      }
    }]
    frontendIPConfigurations: [{
      name: 'appGwPublicFrontendIp'
      properties: {
        publicIPAddress: {
          id: publicIp.id
        }
      }
    }]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]
    httpListeners: [
      {
        name: 'http_listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', agwName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', agwName, 'port_80')
          }
          protocol: 'Http'
        }
      }
      {
        name: 'https_listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', agwName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', agwName, 'port_443')
          }
          protocol: 'Https'
          sslCertificate:{
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', agwName, 'ssl_cert')
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'webshop_backend_plain'
        properties: {
          backendAddresses: [{
            fqdn: webShopAppPlain.properties.defaultHostName
          }]
        }
      }
      {
        name: 'webapp_backend_plain'
        properties: {
          backendAddresses: [{
            fqdn: aspWebAppPlain.properties.defaultHostName
          }]
        }
      }
      {
        name: 'webshop_backend'
        properties: {
          backendAddresses: [{
            fqdn: webShopHostname
          }]
        }
      }
      {
        name: 'webapp_backend'
        properties: {
          backendAddresses: [{
            fqdn: webAppHostname
          }]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'https_backendsettings'
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: true
        }
      }
      {
        name: 'https_backendsettings_plain'
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: true
          path: '/'
        }
      }
    ]
    redirectConfigurations: [{
      name: 'http_to_https'
      properties: {
        redirectType: 'Permanent'
        includePath: true
        includeQueryString: true
        targetListener: {
          id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, 'https_listener')
        }
      }
    }]
    requestRoutingRules: [
      {
        name: 'http_to_https_redirect_rule'
        properties: {
          priority: 1000
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, 'http_listener')
          }
          redirectConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', agwName, 'http_to_https')
          }
        }
      }
      {
        name: 'https_to_backend_rule'
        properties: {
          priority: 1010
          ruleType: 'PathBasedRouting'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, 'https_listener')
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', agwName, 'url_path_map')
          }
        }
      }
    ]
    urlPathMaps:[
      {
        name: 'url_path_map'
        properties: {
          defaultBackendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webapp_backend')
          }
          defaultBackendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'https_backendsettings')
          }
          pathRules: [
            {
              name: 'shopPlainPath'
              properties: {
                paths: ['/shopplain/*', '/shopold/*']
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webshop_backend_plain')
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'https_backendsettings_plain')
                }
              }
            }
            {
              name: 'webAppPlainPath'
              properties: {
                paths: ['/appplain/*', '/appold/*']
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webapp_backend_plain')
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'https_backendsettings_plain')
                }
              }
            }
            {
              name: 'shopPath'
              properties: {
                paths: ['/shop/*']
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webshop_backend')
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'https_backendsettings')
                }
              }
            }
            {
              name: 'webAppPath'
              properties: {
                paths: ['/app/*']
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webapp_backend')
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'https_backendsettings')
                }
              }
            }
          ]
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.0'
    }
  }
}

output webShopHostname string = webShopHostname
output webAppHostname string = webAppHostname
output agwFqdn string = publicIp.properties.dnsSettings.fqdn
