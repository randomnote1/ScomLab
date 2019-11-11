#Requires -Version 3.0
#Requires -Modules Az.Accounts,Az.Resources,Az.Storage

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
        $selectedLocation = Get-AzLocation | Out-GridView -PassThru
        $Location = $selectedLocation.Location
    }

    New-AzResourceGroup -Name $LabName -Location $Location > $null
}

# Deploye the environment
$params = @{
    ResourceGroupName = $LabName
    TemplateUri = 'https://raw.githubusercontent.com/randomnote1/ScomLab/CreateDomain/src/templates/azuredeploy.json'
    TemplateParameterObject = @{
        LabName = $LabName
        adminUsername = $ComputerAdminUserName
        adminPassword = $ComputerAdminPassword
        domainName = 'DanLab.local'
        dnsPrefix = $LabName.ToLower()
        storageAccountType = $StorageType
    }
}
New-AzResourceGroupDeployment @params

# Deploy SQL infrastructure

if ( -not $SqlOnly )
{
    # Install SQL Server
    
    # Deploy SharePoint supporting infrastructure

    # Deploy SharePoint Servers
}
