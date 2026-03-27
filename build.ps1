using namespace System.Management.Automation

[CmdletBinding()]
param(
	[Parameter(ValueFromPipeline)]
	[SemanticVersion[]]$Versions,
	#The minimum version to build for. This should be increased when EOL dates are reached.
	[SemanticVersion]$minimumPSVersion = '7.4',
	#For now, our build process is the same for both. This may change in the future
	$Distributions = @(
		'noble-chiseled'
		'azurelinux3.0-distroless'
	),
	#Map the architectures to the release nomenclature we use.
	[string[]]$Architectures = @('amd64', 'arm64'),
	$LocalImageName = 'powershell',
	$remoteImageName = 'ghcr.io/justingrote/powershell',
	#Known bad versions for whatever reason
	$skipVersions = @(
		'powershell:7.5.0-preview.3-noble-chiseled'
		'powershell:7.5.0-preview.3-azurelinux3.0-distroless'
		'powershell:7.5.0-preview.2-noble-chiseled'
		'powershell:7.5.0-preview.2-azurelinux3.0-distroless'
		'powershell:7.5.0-preview.1-noble-chiseled'
		'powershell:7.5.0-preview.1-azurelinux3.0-distroless'
	),
	#Push to remote repo
	[switch]$Push,
	#Overwrite existing remote images. This is only generally needed if you made a change to the build process and want to rebuild and push the same versions again. By default, if the image already exists remotely, it will skip the build and push process for that image. Use this switch to override that behavior and force a rebuild and push for all specified versions.
	[switch]$Clobber,
	#By default, does not rebuild images that already exist. Use -Force to override.
	[switch]$Force
)

function Write-GitHubActionError {
	param(
		[Parameter(Mandatory = $true)]
		$ErrorRecord
	)

	$ex = $ErrorRecord.Exception
	$msg = if ($ex) { $ex.Message } else { $ErrorRecord.ToString() }
	$stack = if ($ex -and $ex.StackTrace) { $ex.StackTrace } elseif ($ErrorRecord.ScriptStackTrace) { $ErrorRecord.ScriptStackTrace } else { '' }
	$file = $ErrorRecord.InvocationInfo.ScriptName
	$line = $ErrorRecord.InvocationInfo.ScriptLineNumber
	$column = $ErrorRecord.InvocationInfo.OffsetInLine

	$text = $msg
	if ($stack) { $text += "`n`nStacktrace:`n$stack" }

	# Escape characters for GitHub Actions workflow commands
	$text = $text -replace '%', '%25'
	$text = [regex]::Replace($text, '\r?\n', '%0A')
	$text = $text -replace '\[', '%5B'
	$text = $text -replace '\]', '%5D'

	if ($file) {
		Write-Host "::error file=$file,line=$line,col=$column,title=::$text"
	} else {
		Write-Host "::error::$text"
	}
}

trap {
	Write-GitHubActionError $_
	exit 1
}

function Get-AdditionalTags {
	param(
		$version,
		$releaseMajorMinorVersion,
		$distribution,
		$latestTag
	)
	[string[]]$additionalTags = @()
	if (-not $version.PreReleaseLabel -and -not $version.BuildLabel) {
		if ($latestTag.Add('latest')) {
			$additionalTags += 'latest'
		}
		if ($latestTag.Add($version.Major)) {
			$additionalTags += $version.Major
		}
		if ($latestTag.Add($releaseMajorMinorVersion)) {
			$additionalTags += $releaseMajorMinorVersion
		}
		if ($latestTag.Add($version)) {
			$additionalTags += $version
		}
		#LTS tag processing
		if ($version.Minor % 2 -eq 0) {
			$majorLtsTag = "$($version.Major)-lts"
			if ($latestTag.Add($majorLtsTag)) {
				$additionalTags += $majorLtsTag
				if ($latestTag.Add('lts')) {
					$additionalTags += 'lts'
				}
			}
		}
		#Distro tag processing
		if ($latestTag.Add($distribution)) {
			$additionalTags += $distribution
		}
	}
	if ($version.PrereleaseLabel) {
		if ($latestTag.Add('preview')) {
			$additionalTags += 'preview'
		}
	}
	return , $additionalTags
}

function Push-ImageTags {
	param(
		$powershellImageTag,
		$remoteImageName,
		$powershellTag,
		$additionalTags
	)
	[string[]]$pushTags = $powershellTag
	if ($additionalTags) {
		$pushTags += $additionalTags
	}
	$pushArgs = @(
		'--compression-format', 'gzip'
		'--add-compression', 'zstd:chunked'
	)
	foreach ($tag in $pushTags) {
		$remoteTag = "${remoteImageName}:$tag"
		Write-Verbose "📤 Pushing $powershellImageTag to $remoteTag"
		[string[]]$podmanLogs = @()
		podman manifest push @pushArgs $powershellImageTag $remoteTag *>&1 |
			ForEach-Object {
				$podmanLogs += $_
				Write-Debug "${remoteTag}: $_"
			}
		if ($LASTEXITCODE -ne 0) {
			Write-Error "podman Push Failed for tag ${tag}: `n $($podmanLogs -join '`n')"
			continue
		}
	}
}

function Build-Container {
	param(
		$release,
		$distribution,
		$version,
		$releaseMajorMinorVersion,
		$powershellTag,
		$powershellImageTag,
		$Architectures
	)

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
		return
	}

	if (-not $dotnetVersion) {
		Write-Error "No matching distro Image for PowerShell version $releaseMajorMinorVersion"
		return
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
			'--platform', ($platforms -join ','),
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
			return $null
		}

		#Basic Sanity Check
		# TODO: Test in amd64 devcontainer
		$testValue = 'ValidContainer'
		$testResult = & podman run --rm $powershellImageTag "'$testValue'"
		if ($testResult -ne $testValue) {
			Write-Error "PowerShell Image $powershellImageTag failed basic PowerShell script test"
			return $null
		}

		#Add annotations
		$annotations = @{
			'org.opencontainers.image.source'      = 'https://github.com/JustinGrote/PowerShell-Containers'
			'org.opencontainers.image.title'       = "PowerShell Runtime Container $($version.ToString()) for $distribution"
			'org.opencontainers.image.description' = 'Run PowerShell in a low footprint, high performance, and secure environment'
			'org.opencontainers.image.licenses'    = 'MIT'
			'org.opencontainers.image.authors'     = 'Justin Grote'
			'org.opencontainers.image.version'     = $version.ToString()
			'org.opencontainers.image.revision'    = $release.tag_name
			'org.opencontainers.image.created'     = (Get-Date -Format 'o')
		}

		foreach ($annotation in $annotations.GetEnumerator()) {
			Write-Verbose "🏷️ $($annotation.Key)=$($annotation.Value)"
			$annotateArgs = @(
				'--index'
				'--annotation'
				"$($annotation.Key)=$($annotation.Value)"
			)
			& podman manifest annotate @annotateArgs $powershellImageTag | Out-Null
			if ($LASTEXITCODE -ne 0) {
				continue
			}
		}

		# Return the tag if successful
		return $powershellTag

	} catch {
		Write-Host -Fore Magenta $podmanLogs
		throw
	} finally {
		Pop-Location
	}
}

#region Main

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

#These releases are what we will actually build and push, but we still need to "process" all releases to accurate determine the rollup tags like 7, latest, lts, etc.
[SemanticVersion[]]$selectedReleases = $Versions ?
($pwshReleases | Where-Object { $Versions -contains $_.Version }).Version :
$pwshReleases.Version

if (-not $selectedReleases) {
	$noVersionFoundMessage = $Versions ? "No matching versions found for specified versions: $($Versions -join ', ')." : "No versions found greater than minimum version $minimumPSVersion."
	Write-Warning $noVersionFoundMessage
	return
}

#A hash mapping used to easily map and store the state of the latest tags
[System.Collections.Generic.HashSet[string]]$latestTag = @()

[string[]]$existingImages = & podman images $LocalImageName --format '{{.Tag}}'
#Generate the Azure Linux Distroless Images
foreach ($release in $pwshReleases) {
	foreach ($distribution in $Distributions) {
		[SemanticVersion]$version = $release.Version
		[string]$releaseMajorMinorVersion = $version.Major, $version.Minor -join '.'

		$powershellTag = "$version-$distribution"
		$powershellImageTag = "$LocalImageName`:$powershellTag"

		$isSelectedRelease = $selectedReleases -contains $Version

		$doBuild = $true
		if (-not $isSelectedRelease) {
			Write-Verbose "⚪ Skipping build for non-selected image $powershellImageTag"
			$doBuild = $false
		}
		if (-not $Force -and $existingImages -contains $powershellTag) {
			Write-Verbose "⚪ Skipping build for already built image $powershellImageTag"
			$doBuild = $false
		}
		$remoteExists = & podman manifest inspect "${remoteImageName}:$powershellTag" *>&1
		if ($LASTEXITCODE -eq 0 -and -not $Clobber) {
			Write-Verbose "⚪ Skipping build for already existing remote image ${remoteImageName}:$powershellTag. Specify -ForcePush to override"
			$doBuild = $false
		}


		if ($doBuild) {
			if ($skipVersions -contains $powershellImageTag) {
				Write-Verbose "🔨❌ Skipping known bad image $powershellImageTag"
				continue
			}
			Write-Verbose "🔨 Building PowerShell $powershellImageTag for distribution $distribution"
			$buildContainerParams = @{
				release                  = $release
				distribution             = $distribution
				version                  = $version
				releaseMajorMinorVersion = $releaseMajorMinorVersion
				powershellTag            = $powershellTag
				powershellImageTag       = $powershellImageTag
				Architectures            = $Architectures
				LocalImageName           = $LocalImageName
				remoteImageName          = $remoteImageName
				Push                     = $Push
				Force                    = $Force
				latestTag                = $latestTag
			}
			$returnedTag = Build-Container @buildContainerParams
			if ($null -eq $returnedTag) {
				Write-Error -ErrorAction Continue "❌ Failed to build image for PowerShell version $version on distribution $distribution"
				continue
			}
		}

		#Check for rollup tag candidates. Since we start with Azure Linux, it will always default to those distro images first. This must run for EVERY POSSIBLE RELEASE regardless of build to ensure accurate tagging.
		[string[]]$additionalTags = Get-AdditionalTags -version $version -releaseMajorMinorVersion $releaseMajorMinorVersion -distribution $distribution -latestTag $latestTag

		if ($additionalTags) {
			Write-Debug "Additional Tags detected for ${powershellImageTag}: $($additionalTags -join ', ')"
			if ($doBuild) {
				[string[]]$psExtraTags = $additionalTags | ForEach-Object {
					"${LocalImageName}:$_"
				}
				Write-Verbose "🏷️ Adding Tags: $psExtraTags"
				podman tag $powershellImageTag @psExtraTags
			}
		}

		if ($Push -and $isSelectedRelease) {
			$pushImageTagsParams = @{
				powershellImageTag = $powershellImageTag
				remoteImageName    = $remoteImageName
				powershellTag      = $powershellTag
				additionalTags     = $additionalTags
			}
			Push-ImageTags @pushImageTagsParams
		}
	}
}
#endregion Main