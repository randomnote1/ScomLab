#Reqires -Modules Az

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [string]
    $LabName,

    [Parameter(Mandatory = $false)]
    [string]
    [ValidateSet('AzureCloud','AzureUSGovernment')]
    $AzureEnvironmentName = 'AzureUSGovernment',

    [Parameter(Mandatory = $false)]
    [string]
    $Location,

    [Parameter()]
    [String]
    $ComputerAdminUserName = 'LocalAdmin',

    [Parameter(Mandatory = $true)]
    [SecureString]
    $ComputerAdminPassword,

    [Parameter(Mandatory = $false)]
    [switch]
    $SqlOnly
)

# Define static variables
$StorageType = 'Standard_LRS'
$VMSize = 'Standard_D1_V2'

# Get the path to the template files
$templateDir = Join-Path -Path $PSScriptRoot -ChildPath 'templates'

# Log into Azure
try 
{
    Get-AzSubscription -ErrorAction Stop | Out-Null
}
catch
{
    Connect-AzAccount -Environment $AzureEnvironmentName
}

# Create the resource group
try
{
    Get-AzResourceGroup -Name $LabName -ErrorAction Stop | Out-Null
}
catch
{
    if ( [string]::IsNullOrEmpty($Location) )
    {
        # Select a location for the resource group
        $selectedLocation = Get-AzureRmLocation | Out-GridView -PassThru
        $Location = $selectedLocation.Location
    }

    New-AzResourceGroup -Name $LabName -Location $Location > $null
}

# Determine the BLOB storage domains
$blobStorageDomains = @{
    'AzureCloud' = 'blob.core.windows.net'
    'AzureUSGovernment' = 'blob.core.usgovcloudapi.net'
}
$blobStorageDomain = $blobStorageDomains.$AzureEnvironmentName

# Determine the storageName
$storageAccount = Get-AzStorageAccount -ResourceGroupName $LabName
if ( $storageAccount )
{
    $storageName = $storageAccount.StorageAccountName
}
else
{
    $storageName = "$($LabName.ToLower())$(Get-Date -Format 'yyyyMMddhhmmss')"
    if ( $storageName.Length -lt 3 )
    {
        throw 'The storage name must be at least 3 characters long'
    }
    elseif ( $storageName.Length -gt 24 )
    {
        # Get the first 24 characters of the proposed storage name
        $storageName = $storageName.Substring(0,24)
    }
}

# Determine the VM Prefix
if ( $LabName.Length -gt 9 )
{
    $vmPrefix = $LabName.Substring(0,9)
}
else
{
    $vmPrefix = $LabName
}

# Deploy basic supporting infrastructure
<#
$basicInfrastructureParams = @{
    Mode = 'Incremental'
    ResourceGroupName = $LabName
    TemplateFile = ( Join-Path -Path $templateDir -ChildPath 'Infrastructure-Domain.arm.json' )
    TemplateParameterObject = @{
        LabName = $LabName
        BlobStorageDomain = $blobStorageDomain
        storageName = $storageName
        StorageType = $StorageType
        VMSize = $VMSize
        ComputerAdminUserName = $ComputerAdminUserName
        ComputerAdminPassword = $ComputerAdminPassword
        VMPrefix = $vmPrefix
        DomainControllersPerDatacenter = 2
        ManagementServersPerDatacenter = 1
    }
}
$baseInfrastructureResults = New-AzResourceGroupDeployment @basicInfrastructureParams
#>
New-AzResourceGroupDeployment -ResourceGroupName $LabName -TemplateUri https://raw.githubusercontent.com/randomnote1/ScomLab/CreateDomain/src/templates/azuredeploy.json


# Deploy domain infrastructure

# Deploy SQL infrastructure

if ( -not $SqlOnly )
{
    # Install SQL Server
    
    # Deploy SharePoint supporting infrastructure

    # Deploy SharePoint Servers
}