#Requires -Version 3.0
#Requires -Modules Az.Accounts

param
(
    [Parameter()]
	[System.String]
	$LabName = 'ScomLab',
	
	[Parameter(Mandatory = $false)]
    [string]
    [ValidateSet('AzureCloud','AzureUSGovernment')]
    $AzureEnvironmentName = 'AzureUSGovernment',
	
	[Parameter()]
	[System.String]
	$Location,

	[Parameter()]
    [String]
    $ComputerAdminUserName = 'LocalAdmin',

    [Parameter(Mandatory = $true)]
    [SecureString]
    $ComputerAdminPassword,
    
	[Parameter()]
	[System.Management.Automation.SwitchParameter]
	$UploadArtifacts,
    
	[Parameter()]
	[System.String]
	$templateFile = 'azuredeploy.json',
    
	[Parameter()]
	[System.String]
	$ArtifactStagingDirectory = '.',
    
	[Parameter()]
	[System.String]
	$DSCSourceFolder = 'DSC',
    
	[Parameter()]
	[System.Management.Automation.SwitchParameter]
	$ValidateOnly
)

try
{
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(' ','_'), '3.0.0')
}
catch
{}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Format-ValidationOutput
{
    param
	(
		[Parameter()]
		$ValidationOutput,
		
		[Parameter()]
		[System.Int32]
		$Depth = 0
	)

    Set-StrictMode -Off
    return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
}

# Log into Azure
$azureContext = Get-AzContext | Where-Object -FilterScript { $_.Environment.Name -eq $AzureEnvironmentName }
if ( -not $azureContext )
{
    Connect-AzAccount -Environment $AzureEnvironmentName > $null
	$azureContext = Get-AzContext | Where-Object -FilterScript { $_.Environment.Name -eq $AzureEnvironmentName }
}

# Create the resource group
try
{
    Get-AzResourceGroup -Name $LabName -Location $Location -ErrorAction Stop | Out-Null
}
catch
{
    # Select a subscription
	$azureSubscription = Get-AzSubscription -TenantId $azureContext.Tenant.Id
	if ( $azureSubscription.Count -gt 1 )
	{
		$azureSubscription = $azureSubscription | Out-GridView -PassThru
	}
	
	if ( [string]::IsNullOrEmpty($Location) )
    {
        # Select a location for the resource group
        $selectedLocation = Get-AzLocation | Out-GridView -PassThru
        $Location = $selectedLocation.Location
    }

    New-AzResourceGroup -Name $LabName -Location $Location > $null
}

$templateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $templateFile))
$templateParameterObject = @{
	LabName = $LabName
	ADAdminUserName = $ComputerAdminUserName
	ADAdminPassword = $ComputerAdminPassword
}
$artifactStorageContainerName = $LabName.ToLowerInvariant() + '-stageartifacts'

if ($UploadArtifacts)
{
    # Convert relative paths to absolute paths if needed
    $ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
    $DSCSourceFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCSourceFolder))

    # Update the values of artifacts location and artifacts location SAS token if they are present
    $ArtifactsLocationName = '_artifactsLocation'
    $ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'

    # Create DSC configuration archive
    if (Test-Path $DSCSourceFolder)
	{
        $DSCSourceFilePaths = @(Get-ChildItem $DSCSourceFolder -File -Filter '*.ps1' | ForEach-Object -Process {$_.FullName})
        foreach ($DSCSourceFilePath in $DSCSourceFilePaths)
		{
            $DSCArchiveFilePath = $DSCSourceFilePath.Substring(0, $DSCSourceFilePath.Length - 4) + '.zip'
            Publish-AzVMDscConfiguration $DSCSourceFilePath -OutputArchivePath $DSCArchiveFilePath -Force -Verbose
        }
    }

    # Create a staging storage account name
    $storageAccountName = 'stage' + ((Get-AzContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 19)

    $StorageAccount = (Get-AzStorageAccount | Where-Object{$_.StorageAccountName -eq $storageAccountName})

    # Create the storage account if it doesn't already exist
    if ($StorageAccount -eq $null)
	{
        $StorageAccount = New-AzStorageAccount -StorageAccountName $storageAccountName.ToLower() -Type 'Standard_LRS' -ResourceGroupName $LabName -Location $Location
    }

    # Generate the value for artifacts location if it is not provided in the parameter file
    if ($templateParameterObject[$ArtifactsLocationName] -eq $null)
	{
        $templateParameterObject[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $artifactStorageContainerName
    }

    # Copy files from the local storage staging location to the storage account container
    New-AzStorageContainer -Name $artifactStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue > $null

    $ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
    foreach ($SourcePath in $ArtifactFilePaths)
	{
        Set-AzStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) -Container $artifactStorageContainerName -Context $StorageAccount.Context -Force > $null
    }

    # Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
    if ($templateParameterObject[$ArtifactsLocationSasTokenName] -eq $null)
	{
        $sasToken = New-AzStorageContainerSASToken -Container $artifactStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(8)
		$templateParameterObject[$ArtifactsLocationSasTokenName] = $sasToken.ToString()
    }
}

if ($ValidateOnly)
{
    $testAzResourceGroupDeploymentParameters = @{
		ResourceGroupName = $LabName
		TemplateFile = $templateFile
		TemplateParameterObject = $templateParameterObject
	}
	
	$ErrorMessages = Format-ValidationOutput (Test-AzResourceGroupDeployment @testAzResourceGroupDeploymentParameters)
    
	if ($ErrorMessages)
	{
        Write-Output '', 'Validation returned the following errors:', @($ErrorMessages), '', 'Template is invalid.'
    }
    else
	{
        Write-Output '', 'Template is valid.'
    }
}
else
{
    $newAzResourceGroupDeploymentParameters = @{
		Name = ((Get-ChildItem $templateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))
		ResourceGroupName = $LabName
		TemplateFile = $templateFile
		TemplateParameterObject = $templateParameterObject
		Force = $true
		ErrorVariable = 'ErrorMessages'
	}
	
	New-AzResourceGroupDeployment @newAzResourceGroupDeploymentParameters
    
	if ($ErrorMessages)
	{
        Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
    }
}