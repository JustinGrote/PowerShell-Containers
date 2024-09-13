#These args will vary based on the build
ARG DIST=noble
ARG DOTNET_VERSION=8.0
ARG PS_VERSION=7.4.0

#You wont typically need to vary these args
ARG PS_PACKAGE=powershell-${PS_VERSION}-linux-x64-fxdependent.tar.gz
ARG PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
ARG PS_INSTALL_FOLDER=/opt/microsoft/powershell/7
ARG LANG=en_US.UTF-8
ARG IMAGE=mcr.microsoft.com/dotnet/runtime:$DOTNET_VERSION-$DIST-chiseled

#STAGE: Install PowerShell
FROM alpine AS install-powershell
ARG PS_INSTALL_FOLDER
ARG PS_PACKAGE_URL

RUN mkdir -p $PS_INSTALL_FOLDER
# Download PowerShell and extract it
ADD $PS_PACKAGE_URL /tmp/linux.tar.gz
RUN tar zxf /tmp/linux.tar.gz -C $PS_INSTALL_FOLDER -v
RUN chmod a+x,o-w ${PS_INSTALL_FOLDER}/pwsh
RUN chmod a+x,o-w ${PS_INSTALL_FOLDER}/pwsh.dll
RUN ln -s $PS_INSTALL_FOLDER/pwsh /usr/bin/pwsh

#Cleanup unnecessary items
WORKDIR $PS_INSTALL_FOLDER
RUN <<EOF
ls runtimes | grep -v linux-musl-x64 | xargs rm -rf
# Unnecessary localization
rm -rf zh-Hans zh-Hant cs de es fr it ja ko pl pt-BR tr ru _manifest ref
# Unnecessary modules (you shouldnt need PSGet, your stuff should be bundled)
rm -rf Schemas Modules/Microsoft.PowerShell.PSResourceGet Modules/PackageManagement Modules/PSReadline
#Dont need global tool shim stuff
rm Microsoft.PowerShell.GlobalTool*
rm JetBrains.Annotations.dll
rm Microsoft.PowerShell.*.xml
rm ThirdPartyNotices.txt
rm System.Directory*.dll System.Data.SqlClient.dll System.Data.Odbc.dll
rm System.Drawing.Common.dll System.Speech.dll
rm System.Diagnostics*

# This one might be dicey
rm System.Security.Permissions.dll

# Sadly this must stay even with telemetry disabled
# rm Microsoft.ApplicationInsights.dll
EOF


#STAGE: Configure PowerShell
FROM $IMAGE
ARG PS_INSTALL_FOLDER
ARG TAG
COPY --from=install-powershell /opt/microsoft/powershell /opt/microsoft/powershell
COPY --from=install-powershell /usr/bin/pwsh /usr/bin/pwsh

# Define ENVs for Localization/Globalization
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

#PowerShell Specific: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.4
ENV POWERSHELL_DISTRIBUTION_CHANNEL=JustinGrote-PowerShell-Containers-Chiseled-$TAG
ENV POWERSHELL_UPDATECHECK=Off
ENV POWERSHELL_TELEMENTRY_OPTOUT=1
# # ca-certificates no longer needed: https://learn.microsoft.com/en-us/dotnet/core/compatibility/containers/8.0/ca-certificates-package


# # We don't do apk upgrade because its sensitive to when the build was run, instead we rely on the source alpine images.
ENTRYPOINT [ "/opt/microsoft/powershell/7/pwsh", "-noni", "-f" ]
# # # Set pwsh as the shell for next step and disable any telemetry for builds
# #
# # SHELL ["/opt/microsoft/powershell/7/pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# # # Set the Module Analysis Cache Path
# # ENV PSModuleAnalysisCachePath=/PSModuleAnalysisCache/ModuleAnalysisCache

# # #Prepare the Module Analysis Cache
# # RUN <<EOF
# #   while (!(Test-Path $env:PSModuleAnalysisCachePath)) {
# # 		Write-Host "Waiting for $env:PSModuleAnalysisCachePath"
# # 		# Cache takes at least 10 seconds
# # 		Start-Sleep 6
# #   }
# # EOF

# # SHELL ["pwsh"]
# # CMD [ "pwsh" ]