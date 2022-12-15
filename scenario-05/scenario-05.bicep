// must be unique within azure
param webshopName string = 'webshop-agw-demo-05'
param webappName string = 'app-agw-demo-05'
param sqlServerName string = 'sql-agw-demo-05'

// additional parameter
param agwName string = 'agw-demo-05'
param lawName string = 'law-agw-demo-05'
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
  name: 'sqldb-agw-demo-05-catalogdb'
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
  name: 'sqldb-agw-demo-05-identity'
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
  name: 'pip-agw-demo-05'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'agw-demo-05'
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
  name: 'vnet-agw-demo-05'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'vnet-agw-demo-05-subnet'
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
  name: 'plan-demo-05'
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
// webshop-agw-demo-05.azurewebsites.net
var webShopHostname = webShopApp.properties.defaultHostName
var webAppHostname = aspWebApp.properties.defaultHostName

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
        data: 'MIIK0QIBAzCCCo0GCSqGSIb3DQEHAaCCCn4Eggp6MIIKdjCCBg8GCSqGSIb3DQEHAaCCBgAEggX8MIIF+DCCBfQGCyqGSIb3DQEMCgECoIIE/jCCBPowHAYKKoZIhvcNAQwBAzAOBAibLG8AgATF3gICB9AEggTYLJI3fuKLPX2UFeQmKl7BVDK0z95vAm7Zk7Ow8hD44A+lgSDhnK//Y+3daieOnwQmePq5s+yNTG5PC6gx+SmWSOivc8hHKF+CkbCdj4jvT/NWnPIZkK1mLNKxnyNVOJ+p++Nn5scDM3QlvrfNIjQlPjHTuMyU7K4DaTfZDc7M4lPv7rn/pml2gZ5/HF6hXDmPNwlsBJB71yeKxywF/bAJ4A1sl3JtiVWK1etoBMFvRZAv9vMEnPbUAr1qPu974RJv2gMR6MtfQ/vii/LltBDMHWc+cZ+O5nPVw5LBRntHlqG+avTKGhY/QxwnXcddA3gJkR0h2HyPRTA4SOd5lo4662hHDwNWP/ngO1l5AtNfAAvwvVkvwlrMIrYlujLguf6zhQvE/gCTQRsmWfOpQyfl7g2E4NbmrRPvYMtcJOhAB4GgMRvoYGQKwH7cAcaE6AC9MoFzqo8CLdMlxybp+7UgzGXim1r0/P+jrR32id7fbxpQKxvomoBaD6i5eWPVhtyooEjeu7SZBC882h1674jTpqVx//OOk2QebfMYFJWL17IKwmy27pvWDCPlU3a/NpMqpYNDgFmX8hs+tNVTUjovUtU39DKrzpvvmfNDid+qkKFfDxzBeP44Jp5SJPPvwgXboJDx+dgv4IQrJT8XcoY7vcHRC9U48vynYtztra6wkyrl4Q5m+td/3xIUJgruCTfu8I7TpJy8Jvdxd0aT0gHWJT9DZU3zkHI4DQHxFmYYLuHYClIQdXzt8s7R9P0wJ+pO0ShSDPioKDmEpnTIL3byjkxT8hfWie++oJ7QA+8zMonBESl+lK6pV5XcFqrj+CIDPfUWtV6vUb1THyNmWlFOxBI3g/ipVMlOHXj0j3EVHeY2tRBusFGQkAOc247pRFb1vmyTkNhtgEIhdNdVPWe5kQs1++CooTTRYAYYccC0XtiWNoiLjyDualIxYcElMYe7hZ0Dlp2HL/CjXV2VPppJ74YuToptADuo6LRNdNbUZbJI9dZYdDBwAEU1PQe2UbaMkATqECeGxsPx3xdNsWrOif3CzRjOF0ehTUg+Zn53yRzW9dUUq6m5OG9tXXapEm6xzpn4lTgVczdDz66W6H113UBQsiUOFPddvZzP4LTUH9HAm1n6rxuCq4BGh0IdtMrBzxxmWXHQgr1q/J8rjJZw6DTQvigxbnwlOS6+CUUatqh4U6mBRxQyGofqVuQSMvr+xnnCFG2m5XKvxVNL6NK2OKqOO13dIdwhV4hppyp8sFQo1zNCTcMkWZRFB4IRHr4eIbHt8zlnnIbIBYtW8fh8Ima0Rg9evf68OjWMwStDNvNq3gPprnNkZ4t+s+SMb9d8nbW7S4t8DLaEANEU4PoDxkyY5i6gUbdnRE2XE185UyLMKClm5dceFItbH63AS6zHhhAbTLdes+jUqnZeZZQQC81WqBybuo0irmj7vHD1UQfjNHtqHXy4Vu6NVBn6YgWYsRSWeq/2EQhIS7myiqatyJfj/8XrNSgTjL754YoZD8AiYceAcM3Qc+H12CqrA4XprVE4cPYxh9HMtPR5NI2K5UrHUvoLE5zkIzwiYPSzWhqQ7Stffbvo5mzC4F/6FIFS99yHfSOfRx3bQH/WZqU22BiAUtMqz3vlhAE6peQujwRSX9cyNMrwZjGB4jANBgkrBgEEAYI3EQIxADATBgkqhkiG9w0BCRUxBgQEAQAAADBdBgkqhkiG9w0BCRQxUB5OAHQAZQAtADQANgA5AGUANAA5ADAAMwAtADYAMgAwADMALQA0AGIAZQBlAC0AOAA2ADEANwAtADIAYgBjAGUAZgAwAGQAOQA4ADUAYQA0MF0GCSsGAQQBgjcRATFQHk4ATQBpAGMAcgBvAHMAbwBmAHQAIABTAG8AZgB0AHcAYQByAGUAIABLAGUAeQAgAFMAdABvAHIAYQBnAGUAIABQAHIAbwB2AGkAZABlAHIwggRfBgkqhkiG9w0BBwagggRQMIIETAIBADCCBEUGCSqGSIb3DQEHATAcBgoqhkiG9w0BDAEDMA4ECCnH+q3xwuAnAgIH0ICCBBhfuvrKQ8HyYVvJfkUuHW3aY2WReQNlAfnM5msqFyvM88A9SL2rIOVbdCemB8bzR9GBR6w+xAEYNhqzHype7bOeC2fOdveAmICkPJKc9/vu0E+mkFqC8rTFe//cgmPx0a71QSARRy/JPIJJ5KWQyioPosu8XZ83kRMjgjaFThWxMZQqQKWTXV1SSvQACDTUxR3xqIqtFxipFP0riPUz17q5/plM1aOBLWNwkk+JbSICQ3gaCdIREPo0ZbF0Yo0d/vG3a9HTGro7XABHyEMuevYUSyrGiqCOwciPQq2b5hMIp3U2fptKhEL9rYSfIKFBE86skzGDMS55riEr9uwHap+IsjKno4q/0gcizpXxvrSYw9Fk69Z+KJo/4crmmK2oeexpH/zhzpckRLiD/XZQU8/AcrANM9A9lgTP4hIdHBhIBLeZux7fgKXnjypHZGhu80nccU4HHw16qq8Dg9fW+Ee9HR4XvCmCzDZ3+WZ4ZA22TTuZAs4TJN0dbD/QrFO9TWcbhoejywzxTPV6hsSjt4RFnjd8q5qQoAFeRk2pJHTzXwZBuTQfWuLgENIzgtRkOGOBIYbpN8tVyLS1WyASkW9XqKKnHPrVzgXax9e6xkd1fuZnz7L5q+YnWsXiZpPF2WqEGDl9FvbzPcZxrKVsBMIOlT+3GJEEkFaNT2w+1C/E1p8LWG4UWtQZ73r/87zl4/XD8dAP5+yaTuFqi5s82dZjXeaIMWVcEmYtGWWMgcJT4PSFxc46mAm7NPe0qqr5W8r3pCZLTm04G5yb7brDQgXfudjqqOG/4VsLRhgyxP/s4z524ZXLm+uJCJkyl0i+Al2iDKoWg+42lMFYb9Ll0EpupOF5Bu1KOjESqBN3TaD4LH9phk1RmJP9trMiO0vDNJjNpJH+jl3jTKobi5cFnfOt+hnNIBcGOE6fgwCoOE8FVRBtxT+VaAwaBTRT/YMm7pvdgPe2Op3OwJ+y3Aae7YKJ2EGu7tqjFyv6hv5XRbZOHp/M76PM+kNYJP/X1sFAOk0jJJIMHLMQ8rMAlXqec2taDK+HCQyrBLY59PqZpu2HIGG2wNesjc7kJvw8xw65BHQIoGx2uzIq9QrMjNTq4ropz2sTs6hEkCzdSvqV4U62bsS5K6K5bGH9t9lp5uWC0IbBIp6EcmejHaf/+qebqfaYVPm78NUBBeeW8u7Sc1GsgY7jc0G1Oyo0aSqqt3VdVYuLIwd8L2ob1FUgtznQA9KCUnnAY7xtNKbveuaqGlOtnwcnVk1IcHFmSXNs2ywfiy98L5JzwZIGqzt6biPoSDn6AmEX0srenjFXc1/nue8PtqD3a2gYSuOhzpM4w67KByfL2bwFE6Cp8Ft6mrOjTDImHw0zUvVtmRKSsuHnnV0abSPeeEm57KPdMDswHzAHBgUrDgMCGgQUGLZUqDq5mvJ6wZwsp5jn6PqwuZgEFCBan8Bs1VfODKvTNGuKOHPoRJIEAgIH0A=='
        password: 'o@+rflOV2hOh@28do'
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
    backendHttpSettingsCollection: [{
      name: 'https_backendsettings'
      properties: {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
        path: '/'
      }
    }]
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
          defaultRewriteRuleSet: {
            id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', agwName, 'default_rewrite_set')
          }
          pathRules: [
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
    rewriteRuleSets: [{
      name: 'default_rewrite_set'
      properties: {
        rewriteRules: [{
          ruleSequence: 100
          name: 'cleanup_response_headers_rule'
          actionSet: {
            responseHeaderConfigurations: [
              {
                headerName: 'Server'
              }
              {
                headerName: 'X-Powered-By'
              }
              {
                headerName: 'X-AspNetMvc-Version'
              }
              {
                headerName: 'X-AspNet-Version'
              }
            ]
          }
        }]
      }
    }]
    sslPolicy: {
      policyType: 'Predefined'
      policyName: 'AppGwSslPolicy20220101'
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
  }
}


//
// Log Analytics Workspace
//
resource law 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: lawName
  location: location
}

output webShopHostname string = webShopHostname
output webAppHostname string = webAppHostname
output agwFqdn string = publicIp.properties.dnsSettings.fqdn
