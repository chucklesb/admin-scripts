These scripts were written to assist in my day-to-day MSP/sysadmin work.  
  
```
Active Directory/
    AD-Get-Active-Users-Computers.ps1 - Export list of AD Users and Computers and print stats.
    AD-Get-All-DCs.ps1 - Print list of AD domain controllers.
    AD-Get-DNS-Servers.ps1 - Print list of AD nameservers.
    AD-Get-Domain-Admins.ps1 - Print list of AD domain admins.
    AD-Get-FSMO-Role-Holders.ps1 - Print list of AD FSMO role holders.
    AD-Get-Lockout-and-Password-Policies.ps1 - Print AD lockout and password policies.
    Time-DC-or-Standalone.bat - Configure Windows Server NTP settings.
    Time-Domain-Member.bat - Configure Windows workstation NTP settings.

Azure/
    Azure-OATH-Generate-TOTP-URI.ps1 - Takes an Azure OATH CSV file and generates a URI for easy importing into a TOTP generator of your choice.
    Azure-Provision-Environment.ps1 - Create Azure resource group with vnet, gateway, VM, etc.
    Sync-AD-and-Azure.ps1 - Forces inter-site AD replication and triggers an Azure AD delta sync.

cwdeploy/
    bootstrap.ps1 - Build cwdeploy.ps1 (ConnectWise Automate deployment) script and configure deployment GPO.

Miscellaneous/
    disable-sleep-hibernation.bat - Disable hibernation/sleep and power-saving features.
    Get-Installed-Roles.ps1 - Print installed server roles.
    PowerShell-Code-Signing.ps1 - Sign PowerShell scripts with a code signing certificate.
    VPN Profiles/
        Generate-VPN-Profile-Script.ps1 - Generate a user VPN profile creation script.
        Generate-VPN-Profile-Script-Shared.ps1 - Generate a share VPN profile creation script.
```
