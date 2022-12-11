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
// Public IP
//
resource publicIp 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: 'pip-agw-demo-02'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'agw-demo-02'
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
      ipSecurityRestrictions: [
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
    }
  }
}

//
// AGW
//
// webshop-agw-demo-02.azurewebsites.net
var webShopHostname = webShopApp.properties.defaultHostName

var agwName = 'agw-demo-02'
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
        data: 'MIIKyQIBAzCCCoUGCSqGSIb3DQEHAaCCCnYEggpyMIIKbjCCBg8GCSqGSIb3DQEHAaCCBgAEggX8MIIF+DCCBfQGCyqGSIb3DQEMCgECoIIE/jCCBPowHAYKKoZIhvcNAQwBAzAOBAi6C741EodSVAICB9AEggTY0fDNDLzA2EXxV5nKr5ItASoI6cqj6St90p7MX1NvaFnaZdn7EGR6LjnczqnupaDNmLVsBvVUNg004mFPCwpQJB6EQwEWzHFMePLOkV23WKJ5bBedujFcA/kKyHUtV+KdB+Mw6fWDpQF6qo4VkJj+azQtzqJb1xgnj6yblGzi8oK3LQL8Lc/L7h/onVgaZXYscajxLi0VBpU/aI9qJt9llRHxyHZ905rmilOKrzpoAj3NMVjc+BKa0OoPEvzB3/NAWOyaS1qt41iRvTuMgUxbJs727Cfbacwp0ms1N7TpqqtPjv6PPBopfQtOwlhTuy5WXLl/YPRAcHB7GyFCfStgIrPlM2mvhCEuzINSMlVZj7WhEwga4JPZNmGXybqkYWIfmrbNLqVtRsUH9gec2NaZCHZpgeWNmlPbDHkMo20vRguellnG4CRVzcggYbbNF4Gq2d9hJth1AZtqXlaKNAwR1MHA8OtrWn1C0CONa8ADw2tizRnUncykvq/7ePuUs03d6Uoh6oT5Hws2U8YUIHLoh1AcisL4OtqEv23imnkLH8GUiJcBCFmNXgV+A12OnEN9ihDzS591qqT6ePoyoc4life2u6j4OYfmwkerjAWHlvX18wmpCAS8GY8OdALwUwFm7Vj8QfULbgVd5I0qqhjNdyNfPJEbOrogvIYLy7gizkrYs4oTUJ/x8NCKxNXBVIdd50NwlK4g8mm6WhqWxA7zuf6fnKsHy7ktFuiEuDcCBex2bchFI1EmWkSu+WIPZmtAesRXRojW3K5U3MxRL42hlBp+wPgOh/AgFXCd2amtj6+ibPzBjEEuxDXw0GgN1eOkZeMpb5AIhZVyzdrYMFSf30Ze29Ic+kd9QDC2DceVCYEQb2M47Cqz8tAnKewmcElQzprBBVGwG3EjRsdYDcl/3pqhscl5q+8MvG+CTVxgf3MHudq8ir1JSkjzGWoMl9NbG8V7ewLUfvyNLbSgLSQEY4Xu5QCbvZsrHolUzzMMXnv+8PuhphGI6xIepnQJ8VAEnWNUxrukNPGj3NmpccnZiYvv9XqThp01uAicwJ9riHrRy/M2xo/sniRYxSY36hMxtxjg9wFhlOXnRDlFJ8ijVsYHqge3+FWNtY07wpkQxRoE02zYicMzf7TQDIIDHyqQnptCGI733vHFQ4Kt5O6fzUIY0v7B8MaU+MbuoFD5yQDwGl4txv0+yhduCRwOKQwegfq6luik6vKORBTtufbUXfpnV7hmqgPq/CUdWYq3K8eSYoyEDT2uYjINW3hJWXWiL+woZpgvtWhT22OVCLKcuSB0c0GpB5iFaoaA0hnrFDtoLVZBHOS7wjo6mPuVuW7alK65tDxxnk78yfVlcpfVr3xOUVEQwDc/+QOWzPyqaefsBSQTFZ1uMFu8SEaXgs7IAD8FgZyxdFOQS6zCDUMFO63kaoynQIsfyhq/bMkj3HJfl7xzY1YLbrpL+F1Oi9VbHsqgdlNc4uqxNa7NSx9sawULNAVNcIrgQFKqTbIhFpN0zR2h367QDF+dlvRyea2oDIp/6UJ1PGIP15Vgf/fZVx/YoNopPL/PisR/kiWoDWe/hUJqmaMjyBQh/ZD/Jj4AtXTewky0IgNG3JWuyg/roFzWxLoYkr3ke9X+5sOEjMMu3IcIf0t0eDGB4jANBgkrBgEEAYI3EQIxADATBgkqhkiG9w0BCRUxBgQEAQAAADBdBgkqhkiG9w0BCRQxUB5OAHQAZQAtAGMAOAA2ADgAOAAxADEAZAAtAGQANgBmAGYALQA0ADIAOQAzAC0AOABjAGMAYwAtADEAZQA4ADEAYgA4ADQAMwBkAGEAYgA3MF0GCSsGAQQBgjcRATFQHk4ATQBpAGMAcgBvAHMAbwBmAHQAIABTAG8AZgB0AHcAYQByAGUAIABLAGUAeQAgAFMAdABvAHIAYQBnAGUAIABQAHIAbwB2AGkAZABlAHIwggRXBgkqhkiG9w0BBwagggRIMIIERAIBADCCBD0GCSqGSIb3DQEHATAcBgoqhkiG9w0BDAEDMA4ECCpx9YpcxpIvAgIH0ICCBBBTLCyHPgA5K3J9xjMuGC01QL3X7DllujwrWJFGNGiVJbHkTVzELjzpq7NnzbuCnv0TjIrpWRdkXCueAFRvGX/ofuRKubzLE91ezQff0JP2MRsZAvmI35UXbGsdmWyr/l51cZ0Ug78qYWuw/GREFiq46aJh7J8Zf0R16rlkKPz4svDUk1CR1sNVZEbfLaJLN+aWUi7Q7virCoUedm2LslFVCjV5Y2/OJEY9Z+ooMSdXjbaUBAOwgoB8y3IM3y8YdB+pSONGOXbQehzH35Tw3le6WpsnDA0wX7bAHE/q90Gds0/d5rxCcj07bW55MzOoEeK74bNsNTJHDTnYDWJOqv5cC9PuHilriZExlAzz+zrncDIj6E5weLx2UVu01WYsLweHqlnZs95nJAbTTABQ6H/dAqvVkH2uoVrP57nUi9dYxUPLQ8s46FF9pZf4HDad4oGQBtfkw04Q8xOBJmS7DGh5K9q2psENMbQnUd1Z96KWBMJNhxqvPLFdkky/bOPHiiX40hISJG01F9kKTgV2rN5f8wmMyA/VoZ+CcKqVVoP62YQpyimHK/YNXT0yL5jYYF7jI+jPB096ckB6juMxCtNoTu8BYjcKfW7+wxvSWzIwxoyJ3PAiqBdgztu6RbQj0MgkJS/Zy+x7vfGzZIc+XptZ7G9/tbmhCOwlWYCMA2H75piaC9H3LI5fpY13sqSjv/zxVq20adc0Z1rNFIoNDisD4Fem6FEPlqhOlqpeh7Y0V4o/53+YVeQEPOkGz5qzShTx/yu1XNLdCILMJmuwdMuGFXn8mj5GX8FfS3aAvSvUA9atxbkcMdUr3BZ5lcT8rq8kQA/bI3nOuj8V3ko/89+28lIMROHMJXZt0rMxTnD0R/Y63uf+WarzTpc5CWd0zZIiGQmZWYBwsx1nOtt1E5AS5OIeurAxNu0u9Gibxw+hBYWtDQ95T6cfAsfrPnJSohxqg9h9wRk5ZTbPdd9mfPltBPaE6DuZ6Or3s3fz9illGQbhyCyfIA6OPT53xXHCiWKT3WhVmUQj4pZBS0JkfU/hTJlTT0XYRAGEEAikjaFIMfz++P979ojexenBgpyl+VMb2fDuwXuqkpDPlH7ajEPPvFmek2JaNqsc6ZbcFGAt/GYyFNm46PjSPhZCWkmvgaRMDvFGNYmJ+02J2kE4YjtK7PPs7zOLbMpZUZJRBlcDNL+qxaSsAV3Tt2CQH10UjV1uZTqULvRupB38Z+UTRENJrsDcUg7DenwuZ4y57x0NkVgCDwyizczTezLEYE5Noqz14NbYsObAEj2kxkOJ6O4T8/K0klzsfGjnQ76R9r2J1RQ55G6fTjL7Hhe4jlPe1OE48bJH+U1TkKTTdK+zhZcPFpRGJdfwtuJL8WuHx+uB2DA7MB8wBwYFKw4DAhoEFCes125HAx31m4hwfeozM08lxR6QBBS/+kkQxS+qVX2pQsfo+IiwqOzg0wICB9A='
        password: '##a0z9kL2@akMtpZk'
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
    backendAddressPools: [{
      name: 'webshop_backend'
      properties: {
        backendAddresses: [{
          fqdn: webShopHostname
        }]
      }
    }]
    backendHttpSettingsCollection: [{
      name: 'https_backendsettings'
      properties: {
        port: 443
        protocol: 'Https'
        pickHostNameFromBackendAddress: true
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
        name: 'https_to_webshop_rule'
        properties: {
          priority: 1010
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', agwName, 'https_listener')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', agwName, 'https_backendsettings')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', agwName, 'webshop_backend')
          }
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
output agwFqdn string = publicIp.properties.dnsSettings.fqdn
