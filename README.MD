# PowerShell Runtime Containers

![PowerShell Containers](images/README/image.png)

This repository contains some modern container builds for running PowerShell scripts in a small footprint, minimal dependency, small security surface area.

## Quick Start
`docker run ghcr.io/justingrote/powershell '"Welcome to PowerShell $($PSVersionTable.PSVersion)"'`

> Welcome to PowerShell 7.5.0

## Popular/Recommended Tags
Unless otherwise specified, the base distro is [Azure Linux 3.0 distroless](https://github.com/dotnet/dotnet-docker/blob/main/documentation/azurelinux.md)
* `latest` - latest stable version
* `lts` - latest lts version
* `7` - latest 7.x version
* `7-lts` - latest 7.x lts version (e.g. 7.4.x but not 7.5.x)
* `7.4` - latest 7.4.x version
* `7.4.0` - "pinned" version to the version you specify
* `azurelinux3.0-distroless` - latest version using [.NET Azure Linux 3.0 distroless](https://github.com/dotnet/dotnet-docker/blob/main/documentation/azurelinux.md)
* `noble-chiseled` - latest version using [.NET Chiseled](https://github.com/dotnet/dotnet-docker/blob/main/documentation/ubuntu-chiseled.md)

## About These Containers

These images run the fxdependent version of PowerShell, with some additional features removed to reduce size:
1. PowerShellGet/PSResourceGet/PackageManagement removed (you should bundle modules into your container directly)
1. Help Removed
1. PSReadline Removed (this is not meant for interactive use)
1. Some unnecessary assemblies for most workloads removed (SQLClient, ODBC, etc.). You should bundle in modern equivalents with your docker image if you need these.
1. Localization Support removed. If there is sufficient demand for a localization-enabled container, I will build a version based on AzureLinux-extra which includes the required localization parts.

The image also runs under a local non-root user by default. 

By default, there is no writable filesystem access besides /tmp and /home/app for security. You can layer in writable filesystems if needed, but it is recommended to mount volumes instead.

## Tagging Strategy
Fully qualified tags describe the complete variant of the container. Shorter tags represent the "latest" version. For example:

`powershell:7.4.7-dotnet-8.0.14-azurelinux3.0-distroless-amd64` - Fully Qualified module name
`powershell:7.4.7-dotnet-8.0.14-azurelinux3.0-distroless` - Assumes amd64 (most popular image architecture)
`powershell:7.4.7` - Assumes AzLinux3.0 distroless amd64
`powershell:7.4` - Maps to latest 7.4 servicing branch (e.g. will automap to 7.4.8 if released)
`powershell:7` - Maps to latest feature branch (e.g. will automap to latest 7.6.2)
`powershell:latest` - Maps to the latest non-preview version available

I'm still debating how to handle .Net servicing updates, whether we generate a giant matrix of every possible combination, or if we uptag in-place.

## Flavors
* **Azure Linux 3.0 Distroless**: A Microsoft Linux distro optimized for running in cloud workloads.
* **DotNet Chiseled**: A highly stripped down version of Debian barebones optimized to run dotnet applications.

Alpine builds have been deprecated for now in favor of distroless builds. Interactive users should use the official .NET SDK or Devcontainer images.

## Updates
There are plans to auto-generate new images upon new PowerShell release within 24 hours, potentially as soon as a release is posted.

