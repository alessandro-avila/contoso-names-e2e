param name string
param location string
param kubernetesVersion string

@description('Custom tags to apply to the resources')
param tags object = {}

@description('The workspace id of the connected log analytics workspace')
param logAnalyticsId string = ''


var aksDiagCategories = [
  'cluster-autoscaler'
  'kube-controller-manager'
  'kube-audit-admin'
  'guard'
]

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aks-diagnostics'
  scope: aks
  properties: {
    workspaceId: logAnalyticsId
    logs: [for category in aksDiagCategories: {
      category: category
      enabled: true
    }]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2023-02-02-preview' = {
  location: location
  name: name
  properties: {
    dnsPrefix: '${name}-dns'
    kubernetesVersion: kubernetesVersion
    enableRBAC: false
    workloadAutoScalerProfile: {
      keda: {
        enabled: false // Will resort to installing the Helm chart for 2.10 until the add-on is updated
      }
      verticalPodAutoscaler: {
        enabled: true
        controlledValues: 'RequestsAndLimits'
        updateMode: 'Off' // The UpdateMode of vertical Pod Autoscaler can't be changed in preview
      }
    }
    /*
    ingressProfile: {
      webAppRouting: {
        dnsZoneResourceId: ''
        enabled: true
      }
    }*/
    agentPoolProfiles: [
      {
        name: 'systempool'
        osDiskSizeGB: 0 // default size
        osDiskType: 'Ephemeral'
        enableAutoScaling: true
        count: 3
        minCount: 3
        maxCount: 5
        vmSize: 'Standard_DS4_v2'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        maxPods: 250
        nodeLabels: {
        }
        nodeTaints: []
        enableNodePublicIP: false
        tags: tags
      }/*
      {
        name: 'workerpool'
        osDiskSizeGB: 0 // default size
        osDiskType: 'Ephemeral'
        enableAutoScaling: true
        count: 1
        minCount: 1
        maxCount: 20
        vmSize: 'Standard_DS4_v2'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'User'
        maxPods: 250
        nodeLabels: {
        }
        nodeTaints: []
        enableNodePublicIP: false
        tags: tags
      }*/
    ]/*/
    apiServerAccessProfile: {
      enablePrivateCluster: false
      enableVnetIntegration: true
    }*/
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    }
    networkProfile: {
      loadBalancerSku: 'standard'
      networkPlugin: 'azure'
     // networkPluginMode: 'overlay'
      outboundType: 'loadBalancer'
    }
    /*
    nodeResourceGroupProfile: {
      restrictionLevel: 'ReadOnly'
    }*/
    oidcIssuerProfile: {
      enabled: true
    }
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
    addonProfiles: {
      /*azurepolicy: {
        enabled: true
      }*/
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }  
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsId
          useAADAuth: 'true'
        }
      }
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Prometheus custom config for pod annotation scraping
module prometheusConfig '../monitoring/prometheus-config.bicep' = {
  name: 'prometheus-config'
  params: {
    kubeConfig: aks.listClusterAdminCredential().kubeconfigs[0].value
  }
}

@description('The AKS cluster identity')
output clusterIdentity object = {
  clientId: aks.properties.identityProfile.kubeletidentity.clientId
  objectId: aks.properties.identityProfile.kubeletidentity.objectId
  resourceId: aks.properties.identityProfile.kubeletidentity.resourceId
}
output name string = aks.name
output aksOidcIssuer string = aks.properties.oidcIssuerProfile.issuerUrl
