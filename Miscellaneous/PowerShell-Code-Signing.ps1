## PowerShell-Code-Signing.ps1
#
# Sign PowerShell scripts with a code signing certificate
#

# .NET methods for hiding/showing the console in the background
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'

function Show-Console
{
    $consolePtr = [Console.Window]::GetConsoleWindow()

    # Hide = 0,
    # ShowNormal = 1,
    # ShowMinimized = 2,
    # ShowMaximized = 3,
    # Maximize = 3,
    # ShowNormalNoActivate = 4,
    # Show = 5,
    # Minimize = 6,
    # ShowMinNoActivate = 7,
    # ShowNoActivate = 8,
    # Restore = 9,
    # ShowDefault = 10,
    # ForceMinimized = 11

    [Console.Window]::ShowWindow($consolePtr, 4)
}

function Hide-Console
{
    $consolePtr = [Console.Window]::GetConsoleWindow()
    [Console.Window]::ShowWindow($consolePtr, 0)
}

# Includes
Add-Type -AssemblyName System.Windows.Forms

# Functions
function Get-ScriptPath()
{
	$Script:fileScript = New-Object System.Windows.Forms.OpenFileDialog
	$Script:fileScript.InitialDirectory = $pwd
	$Script:fileScript.Filter = 'Windows PowerShell Script (*.ps1)|*.ps1'
	$Script:fileScript.ShowDialog()
	$Script:textboxScript.Text = $Script:fileScript.FileName
	$Script:textboxScript.Refresh()
}

function Sign-Script()
{
	if (-not ($Script:fileScript.CheckFileExists)) {
		$Script:textboxStatus.Text = 'Invalid script path'
		$Script:textboxStatus.Refresh()
	} else {
		if (-not ($Script:comboboxCertificate.SelectedIndex -In 1..$Script:certificates.Count)) {
			$Script:textboxStatus.Text = 'Invalid certificate selection'
			$Script:textboxStatus.Refresh()
		} else {
			$signature = Set-AuthenticodeSignature -FilePath "$($Script:fileScript.FileName)" -Certificate $($Script:certificates[($Script:comboboxCertificate.SelectedIndex - 1)]) -HashAlgorithm SHA256
			if ($signature.SignerCertificate.Thumbprint -ne $($Script:certificates[($comboboxCertificate.SelectedIndex - 1)].Thumbprint)) {
				$Script:textboxStatus.Text = 'Invalid certificate signature'
				$Script:textboxStatus.Refresh()
			} else {
				$Script:textboxStatus.Text = 'Script signed successfully'
				$Script:textboxStatus.Refresh()
			}			
		}
	}
}

# Main
# Get signing certificates
try {
	$certificates = @(Get-ChildItem -Path Cert:\CurrentUser\My -Recurse -CodeSigningCert)
} catch {
	Write-Host "Unable to query code signing certificates"
	Write-Error "$_" -ErrorAction Stop
}
if ( $certificates.Count -lt 1 ) {
	Write-Host "No code signing certificates found"
	Write-Error "$_" -ErrorAction Stop
}

# GUI Configuration
$main_form = New-Object System.Windows.Forms.Form
$main_form.Text = 'PowerShell Code Signing'
$main_form.Width = 795
$main_form.Height = 140
$main_form.Add_Load({Hide-Console})

$labelScript = New-Object System.Windows.Forms.Label
$labelScript.Text = 'Script:'
$labelScript.AutoSize = $true
$labelScript.Location = New-Object System.Drawing.Point(10,15)

$textboxScript = New-Object System.Windows.Forms.TextBox
$textboxScript.Text = ''
$textboxScript.Enabled = $false
$textboxScript.Width = 600
$textboxScript.Location = New-Object System.Drawing.Point(80,10)

$buttonScript = New-Object System.Windows.Forms.Button
$buttonScript.Width = 80
$buttonScript.Height = 20
$buttonScript.Location = New-Object System.Drawing.Point(690,10)
$buttonScript.Text = 'Browse'
$buttonScript.Add_Click({Get-ScriptPath})

$labelCertificate = New-Object System.Windows.Forms.Label
$labelCertificate.Text = 'Certificate:'
$labelCertificate.AutoSize = $true
$labelCertificate.Location = New-Object System.Drawing.Point(10,45)

$comboboxCertificate = New-Object System.Windows.Forms.ComboBox
$comboboxCertificate.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList;
$comboboxCertificate.AutoSize = $true
$comboboxCertificate.Width = 600
$comboboxCertificate.Items.Add('Select a code signing certificate...')
ForEach ($certificate in $certificates) {
	$comboboxCertificate.Items.Add("$($certificate.Subject) ($($certificate.Thumbprint)), expires $($certificate.NotAfter.ToString("M/dd/yyyy"))")
	Remove-Variable certificate
}
$comboboxCertificate.SelectedIndex = 0
$comboboxCertificate.Location = New-Object System.Drawing.Point(80,40)

$buttonCertificate = New-Object System.Windows.Forms.Button
$buttonCertificate.Width = 80
$buttonCertificate.Height = 20
$buttonCertificate.Location = New-Object System.Drawing.Point(690,40)
$buttonCertificate.Text = 'Sign'
$buttonCertificate.Add_Click({Sign-Script})

$labelStatus = New-Object System.Windows.Forms.Label
$labelStatus.Text = 'Status:'
$labelStatus.AutoSize = $true
$labelStatus.Location = New-Object System.Drawing.Point(10,75)

$textboxStatus = New-Object System.Windows.Forms.TextBox
$textboxStatus.Text = 'Idle'
$textboxStatus.Enabled = $false
$textboxStatus.Width = 600
$textboxStatus.Location = New-Object System.Drawing.Point(80,70)

$main_form.Controls.Add($labelScript)
$main_form.Controls.Add($textboxScript)
$main_form.Controls.Add($buttonScript)
$main_form.Controls.Add($labelCertificate)
$main_form.Controls.Add($comboboxCertificate)
$main_form.Controls.Add($buttonCertificate)
$main_form.Controls.Add($labelStatus)
$main_form.Controls.Add($textboxStatus)
$main_form.ShowDialog()
