# [PowerShell Runtime Containers](https://ghcr.io/justingrote/powershell)

![PowerShell Runtime Containers](images/README/image.png)

This repository provides modern container builds for running PowerShell Scripts.

Found at: [ghcr.io/justingrote/powershell](https://ghcr.io/justingrote/powershell)

Optimized for:

🤏 Small Footprint (~140Mb)

⏱️ High Performance

👮 Minimal Security Surface Area

---

https://github.com/user-attachments/assets/c3fb3fd7-cc5d-4146-a7d9-ef823d6d99ed

## ⚡ Quick Start
> [!NOTE]
By default the container will run any powershell script passed to it as an argument, either directly or via stdin.

`docker run ghcr.io/justingrote/powershell '"Welcome to PowerShell $($PSVersionTable.PSVersion)"'`

> Welcome to PowerShell 7.5.0

## 🏷️ Tags
> [!NOTE]
Unless otherwise specified, the base distro is [Azure Linux 3.0 distroless](https://github.com/dotnet/dotnet-docker/blob/main/documentation/azurelinux.md)

* `latest` - latest stable version
* `lts` - latest lts version
* `X` - latest specified major version. For example: `7` is the latest 7.x.x version
* `X-lts` - latest specified major lts version (e.g. `7-lts` is 7.4.Z but not 7.5.Z)
* `X.Y` - latest feature version. For example: `7.4` is latest 7.4.Z version.
* `7.X.Y` - "pinned" version to the version you specify. For example: `7.4.2` will always be `7.4.2`
* `azurelinux3.0-distroless` - latest stable version using [.NET Azure Linux 3.0 distroless](https://github.com/dotnet/dotnet-docker/blob/main/documentation/azurelinux.md)
* `noble-chiseled` - latest stable version using [.NET Chiseled](https://github.com/dotnet/dotnet-docker/blob/main/documentation/ubuntu-chiseled.md)

> [!TIP]
There are direct tags you can pin to a specific version and architecture. These tags should be considered relatively stable but not immutable, as changes to the image build process or bugfixes may be required, but the PowerShell version specified will remain the same.

## 📦 Bundling
To create new container applications, define a new dockerfile that bundles your script.

* [Standalone Script Example](Examples/Script/README.MD)
* [Script with Modules Example](Examples/ScriptWithModules/README.MD)


## About These Containers

These images run the self-contained version of PowerShell on top of the dotnet/runtime-deps container, with some additional features removed to reduce size:
1. PowerShellGet/PSResourceGet/PackageManagement removed (you should bundle modules into your container directly)
1. Help Removed
1. PSReadline Removed (this is not meant for interactive use)
1. Some unnecessary assemblies for most workloads removed (SQLClient, ODBC, etc.). You should bundle in modern equivalents with your docker image if you need these.
1. Localization Support removed. If there is sufficient demand for a localization-enabled container, I will build a version based on AzureLinux-extra which includes the required localization parts.

The images are multi-arch, supporting x64 and arm64-v8.

The image also runs under a local non-root user by default. 

By default, there is no writable filesystem access besides /tmp and /home/app for security. You can layer in writable filesystems if needed, but it is recommended to mount volumes instead.

Alpine builds have been deprecated for now in favor of distroless builds. Interactive users should use the official .NET SDK or Devcontainer images.

While fxdependent is smaller, the self-contained images contain precompliation that result in a huge (50%+) startup CPU and time cost, so the minor extra 30MB or so is considered worth the size increase, especially since the size is a one-time hit.

## Updates

There are plans to auto-generate new images upon new PowerShell release within 24 hours, potentially as soon as a release is posted.
