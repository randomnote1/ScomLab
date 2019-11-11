Configuration Main
{
	param
	(
		[Parameter(Mandatory = $true)]
		[System.String]
		$NodeName,

		[Parameter(Mandatory = $true)]
		[System.String]
		$DomainName,

		[Parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$ADAdminCredential
	)

	Import-DscResource -ModuleName PSDesiredStateConfiguration
	Import-DscResource -ModuleName ActiveDirectoryDsc -ModuleVersion 4.0.0.0

	Node $NodeName
	{
		LocalConfigurationManager
        {
            ConfigurationMode = 'ApplyAndAutoCorrect'
            RebootNodeIfNeeded = $true
            ActionAfterReboot = 'ContinueConfiguration'
            AllowModuleOverwrite = $true
        }

        WindowsFeature DNS_RSAT
        {
            Ensure = 'Present'
            Name = 'RSAT-DNS-Server'
        }

        WindowsFeature ADDS_Install
        {
            Ensure = 'Present'
            Name = 'AD-Domain-Services'
        }

        WindowsFeature RSAT_AD_AdminCenter
        {
            Ensure = 'Present'
            Name = 'RSAT-AD-AdminCenter'
        }

        WindowsFeature RSAT_ADDS
        {
            Ensure = 'Present'
            Name = 'RSAT-ADDS'
        }

        WindowsFeature RSAT_AD_PowerShell
        {
            Ensure = 'Present'
            Name = 'RSAT-AD-PowerShell'
        }

        WindowsFeature RSAT_AD_Tools
        {
            Ensure = 'Present'
            Name = 'RSAT-Role-Tools'
        }

        WindowsFeature RSAT_GPMC
        {
            Ensure = 'Present'
            Name = 'GPMC'
        }

        ADDomain CreateForest
        {
            DomainName = $DomainName
            Credential = $ADAdminCredential
            SafemodeAdministratorPassword = $ADAdminCredential.Password
            DatabasePath = 'C:\Windows\NTDS'
            LogPath = 'C:\Windows\NTDS'
            SysvolPath = 'C:\Windows\Sysvol'
            DependsOn = '[WindowsFeature]ADDS_Install'
        }
	}
}
