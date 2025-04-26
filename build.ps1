using namespace System.Management.Automation

[CmdletBinding()]
param(
	#The minimum version to build for. This should be increased when EOL dates are reached.
	[SemanticVersion]$minimumPSVersion = '7.5',
	#For now, our build process is the same for both. This may change in the future
	$Distributions = @(
		'noble-chiseled'
		'azurelinux3.0-distroless'
	),
	#Map the architectures to the release nomenclature we use.
	[string[]]$Architectures = @('amd64', 'arm64'),
	$LocalImageName = 'powershell',
	$remoteImageName = 'ghcr.io/justingrote/powershell',
	#Push to remote repo
	[switch]$Push
)

$irmParams = @{
	Headers = @{
		Accept                 = 'application/vnd.github+json'
		'X-Github-Api-Version' = '2022-11-28'
	}
	Uri     = 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=100'
}
Write-Verbose 'Fetching Latest PowerShell Releases'
$releases = Invoke-RestMethod @irmParams -Verbose:$false

# Gather releases newer than specified minimumPSVersion
$pwshReleases = $releases
| Select-Object id,
tag_name,
@{
	N = 'Version';
	E = { [SemanticVersion]($_.tag_name -replace '^v') }
},
name,
assets
| Where-Object Version -GT $minimumPSVersion
| Sort-Object Version -Descending

#A hash mapping used to easily map and store the state of the latest tags
[System.Collections.Generic.HashSet[string]]$latestTag = @()

#Generate the Azure Linux Distroless Images
foreach ($release in $pwshReleases) {
	foreach ($distribution in $Distributions) {
		[SemanticVersion]$version = $release.Version
		[string]$releaseMajorMinorVersion = $version.Major, $version.Minor -join '.'

		$powershellTag = "$version-$distribution"
		$powershellImageTag = "$LocalImageName`:$powershellTag"
		$powershellRemoteTag = "$remoteImageName`:$powershellTag"

		Write-Verbose "🟢: Building PowerShell $powershellTag"

		# Fetch the global.json from the commit to determine the .NET version
		$dotnetVersion = (Invoke-RestMethod "https://raw.githubusercontent.com/PowerShell/PowerShell/refs/tags/$($release.tag_name)/global.json" -Verbose:$false).sdk.version

		#Do some massaging to get the correct tag. For example convert 10.0.100-preview.2.25164.34 to 10.0-preview
		$currentDotnetVersion = $dotnetVersion
		$dotnetVersion = $dotnetVersion -replace '^(\d+\.\d+)(\.\d+)-(\w+)\.(\d+)?.+$', '$1.0-$3.$4'
		if ($dotnetVersion -ne $currentDotnetVersion) {
			Write-Debug "Dotnet Preview Version Detected. New Tag: $dotnetVersion"
		} else {
			[Version]$releaseVer = $dotnetVersion
			$dotnetVersion = $releaseVer.Major, $releaseVer.Minor -join '.'
			Write-Debug "Dotnet Version Detected. New Tag: $dotnetVersion"
		}

		if (-not $dotnetVersion) {
			Write-Error "Unable to fetch .NET version for PowerShell version $releaseMajorMinorVersion"
			continue
		}

		if (-not $dotnetVersion) {
			Write-Error "No matching distro Image for PowerShell version $releaseMajorMinorVersion"
			continue
		}


		Push-Location $PSScriptRoot/Containers/Distroless
		try {
			$platforms = $Architectures | ForEach-Object {
				"linux/$_"
			}

			$podmanBuildArgs = @(
				# Pass the version and distribution to the podmanfile
				'--build-arg', "DIST=$distribution",
				'--build-arg', "PS_VERSION=$version",
				'--build-arg', "DOTNET_VERSION=$dotnetVersion"
				'--platform', ($platforms -join ',')
				'--manifest', $powershellImageTag
			)


			Write-Debug "podman Build Args: $($podmanBuildArgs -join ' ')"

			& podman build @podmanBuildArgs . *>&1
			| ForEach-Object {
				$podmanLogs += $_
				Write-Debug "${powershellTag}: $_"
			}

			if ($LASTEXITCODE -ne 0) {
				Write-Error "podman Build Failed: `n $($podmanLogs -join '`n')"
				continue
			}

			#Basic Sanity Check
			# TODO: Test in amd64 devcontainer
			$testValue = 'ValidContainer'
			$testResult = & podman run --rm $powershellImageTag "'$testValue'"
			if ($testResult -ne $testValue) {
				Write-Error "PowerShell Image $powershellImageTag failed basic PowerShell script test"
				continue
			}

			#Check for rollup tag candidates. Since we start with Azure Linux, it will always default to those distro images first.
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

			$psExtraTags = foreach ($tag in $additionalTags) {
				"powershell:$tag"
			}
			podman tag $powershellImageTag @additionalTags

			if ($Push) {
				Write-Debug "Pushing $powershellImageTag to $powershellRemoteTag"
				podman push $powershellImageTag $powershellRemoteTag

				if ($psExtraTags) {
					foreach ($tag in $additionalTags) {
						Write-Debug "Pushing additional tag $tag to $psExtraTags"
						podman push $powershellImageTag "$remoteImageName`:$tag"
					}
				}
			}

		} catch {
			Write-Host -Fore Magenta $podmanLogs
			throw
		} finally {
			Write-Verbose "🤚: Building PowerShell $powershellTag"
			Pop-Location
		}
	}
}