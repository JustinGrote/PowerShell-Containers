FROM ghcr.io/justingrote/powershell
ADD main.ps1 /

# Need this to make RUN work correctly
SHELL [ "/opt/microsoft/powershell/7/pwsh", "-c" ]
# Bootstraps ModuleFast and tells it to install the dependencies present in main.ps1 #requires header
# Default installation is to the /home/app folder which is writable by the user
# If you want modules in a read-only location, use -Destination /usr/local/share/powershell/Modules
RUN <<SCRIPT
iwr bit.ly/modulefast | iex
Install-ModuleFast -Path main.ps1 -Verbose
SCRIPT

CMD ["/main.ps1"]
