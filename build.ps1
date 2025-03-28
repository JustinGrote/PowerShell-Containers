using namespace System.Management.Automation

[CmdletBinding()]
param(
	#The minimum version to build for. This should be increased when EOL dates are reached.
	[SemanticVersion]$minimumPSVersion = '7.4',
	$PSVersionToNetFrameworkMap = @{
		'7.4' = '8.0.14'
		'7.5' = '9.0.3'
		'7.6' = '9.0.3'
		#TODO: Pre-fetch the zip to determine .NET framework version maybe?
		'7.5.0-preview.1' = '8.0.14'
	},
	#For now, our build process is the same for both. This may change in the future
	$Distributions = @(
		'azurelinux3.0-distroless'
		'noble-chiseled'
	),
	$LocalRepo = 'powershell',
	$RemoteRepo = 'ghcr.io/justingrote/powershell'
)

$irmParams = @{
	Headers = @{
		Accept = 'application/vnd.github+json'
		'X-Github-Api-Version' = "2022-11-28"
	}
	Uri = 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=100'
}
Write-Verbose "Fetching Latest PowerShell Releases"
$releases = irm @irmParams -Verbose:$false

# Gather releases newer than specified minimumPSVersion
$pwshReleases = $releases
| Select-Object id,
	@{
		N='Version';
		E={[SemanticVersion]($_.tag_name -replace '^v')}
	},
	name,
	assets
| Where-Object Version -GT $minimumPSVersion
| Sort-Object Version -Descending

#A hash mapping used to easily map and store the state of the latest tags
[System.Collections.Generic.HashSet[string]]$latestTag = @()

#Generate the Azure Linux Distroless Images
foreach ($distribution in $Distributions) {
	foreach ($release in $pwshReleases) {
		[SemanticVersion]$version = $release.Version
		[string]$releaseMajorMinorVersion = $version.Major, $version.Minor -join '.'

		Write-Verbose "🟢: Building PowerShell $version - $distribution"

		# Check for a specific version (usually for preview overrides), then check for the general feature release map
		$dotnetVersion = $PSVersionToNetFrameworkMap[$version.ToString()] ??
			$PSVersionToNetFrameworkMap[$releaseMajorMinorVersion]

			if (-not $dotnetVersion) {
			Write-Error "No matching distro Image for PowerShell version $releaseMajorMinorVersion"
			continue
		}

		$dotnetImageTag = "$dotnetVersion-$distribution-amd64"
		$dotnetImageUri = "mcr.microsoft.com/dotnet/runtime:$dotnetImageTag"
		$powershellImageTag = "$localRepo`:$version-dotnet-$dotnetImageTag"
		$powershellRemoteTag = "$remoteRepo`:$version-dotnet-$dotnetImageTag"

		# Quick sanity check the dotnet image exists
		$manifest = & docker manifest inspect $dotnetImageUri
		if ($LASTEXITCODE -eq 1) {
			Write-Error "Unable to find dotnet image $manifest"
			continue
		}

		Push-Location $PSScriptRoot/AzureLinux
		try {
			$dockerLogs = & docker build --build-arg IMAGE=$dotnetImageUri --build-arg PS_VERSION=$version -t $powershellImageTag . *>&1
			docker tag $powershellImageTag $powershellRemoteTag

			#Basic Sanity Check
			$testValue = 'ValidContainer'
			$testResult = & docker run --rm $powershellImageTag "'$testValue'"
			if ($testResult -ne $testValue) {
				Write-Error "PowerShell Image $powershellImageTag failed basic PowerShell script test"
				continue
			}

			#Check for rollup tag candidates. Since we start with Azure Linux, it will always default to those distro images first. As we have also already
			[string[]]$additionalTags = @()
			if (-not $version.PreReleaseLabel -and -not $version.BuildLabel) {
				if ($latestTag.Add('latest')) {
					Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as latest"
					$additionalTags += 'latest'
				}
				if ($latestTag.Add($Version.Major)) {
					Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as $($Version.Major)"
					$additionalTags += $Version.Major
				}
				if ($latestTag.Add($releaseMajorMinorVersion)) {
					Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as $releaseMajorMinorVersion"
					$additionalTags += $releaseMajorMinorVersion
				}
				if ($latestTag.Add($version)) {
					Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as $version"
					$additionalTags += $version
				}

				#LTS tag processing
				if ($Version.Minor % 2 -eq 0) {
					$majorLtsTag = "$($Version.Major)-lts"
					if ($latestTag.Add($majorLtsTag)) {
						Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as $majorLtsTag"
						$additionalTags += $majorLtsTag
						if ($latestTag.Add('lts')) {
							Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as lts"
							$additionalTags += 'lts'
						}
					}
				}

				#Distro tag processing
				if ($latestTag.Add($distribution)) {
					Write-Verbose "🎯 $powerShellImageTag will be additionally tagged as $distribution"
					$additionalTags += $distribution
				}
			}

			foreach ($tag in $additionalTags) {
				 docker tag $powershellImageTag "powershell:$tag"
				 docker tag $powerShellImageTag "$remoteRepo`:$tag"
			}
		} catch {
			Write-Host -Fore Magenta $dockerLogs
			throw
		} finally {
			Write-Verbose "🤚: Building PowerShell $version - $Distribution"
			Pop-Location
		}
	}
}
