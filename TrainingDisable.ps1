<#
  .Synopsis
    "What About Me" Training Lockout Script
  .DESCRIPTION
    Script that will use a SQL pull to identify the list of individuals who have not completed their required "What About Me" training and pass that list
    through an Active Directory Search which will verify that they do not meet one of a list of exemptions before disabling their account.

    There is a list of configuration variables to change behavior of the script located directly blow the informational comment block.
  

=========================================================================================================================================================================================================
Revision History
=========================================================================================================================================================================================================
Date           |Version         |Change                                                                                                               |Administrator
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
06.25.2024     |v1.0            |Initial Release                                                                                                      |SUaDtL
06.28.2024     |v1.01           |Added if statement to all "write-log" functions to create log directory path if it doesn't exist.                    |SUaDtL
                                |Added $LogFileBasePath to Config Variables so that only one variable needs to be changed for all log output.
=========================================================================================================================================================================================================
Global Variables
=========================================================================================================================================================================================================
Name                            |Description
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
None at Release
=========================================================================================================================================================================================================
Functions
=========================================================================================================================================================================================================
Name                            |Description
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
WAM-SQLLookup                   |This function opens a connection to the WAM Training DB and pulls a list of usernames which are flagged for training.
Write-Log                       |This function writes all actions within this script to a log file.  It is the main log.
Write-LogVIP                    |This function writes actions performed against a VIP account to a log file.
Write-LogEXEMPT                 |This function writes output whenever a user with an exemption is discovered.
WAM-Disable                     |This function disables the account, changes the description, and outputs fail/success to main log.
WAM-ADSearch                    |This function takes the output from WAM-SQLLookup and checks AD for exemptions, writes status to logs, and calls for disable.
Start-Main                      |Sequentializes other functions to properly order the script.
#>
# Load $Date Variable with today's formatted date.  
$Date = (Get-Date -f yyyyMMdd)

#========================================================================================================================                
#                                                CONFIGURATION VARIABLES                                                # 
#                                    Change Below Variables to affect Script Behavior                                   #
#========================================================================================================================
#                                                     GRACE PERIOD                                                      #
#                           Number of days since inprocessing to ignore training noncompliance                          #
$GracePeriod = 30
#========================================================================================================================
#                                                     REPORT ONLY                                                       #
#                       $TRUE will generate a list of noncompliant users, but skip Disable Action                       #
$ReportOnly = $TRUE
#========================================================================================================================
#                                                    OU EXEMPTIONS                                                      #
#                                         $TRUE will exempt from Disable Action                                         #
$VIP = $FALSE # $TRUE Will exempt ALL users in VIP OU
$REL = $TRUE # $TRUE Will exempt ALL users in REL OU
$SCO = $TRUE # $TRUE Will exempt ALL users in SCO OU
#========================================================================================================================
#                                                    EXEMPT GROUPS                                                      #
#                            Add users to these AD groups to exempt them from Disable Action                            #
#                            Alternatively add group names to this array to exempt the group                            #
$Exempt = "VIP No Tng Req", "Temp No Tng Req"
#========================================================================================================================
#                                                      LOG FILES                                                        #
#                                       Set the Output Location of the Log Files                                        #
$LogFileBasePath = "C:\PS\Script_Output\WAM\$Date"                                        
$LockoutListFile = "$LogFileBasePath\LockoutList_$Date.txt"
$LogFileALL = "$LogFileBasePath\LockoutUsers_All_$Date.log"
$LogFileVIP = "$LogFileBasePath\LockoutUsers_VIP_$Date.log"
$LogFileExempt = "$LogFileBasePath\LockoutUsers_EXEMPT_$Date.log"
#========================================================================================================================


#========================================================================================================================
#                                                      SQL LOOKUP                                                       #
#========================================================================================================================

# Create a function that pulls the usernames who are training noncompliant from the WebTraining DB
function WAM-SQLLookup{
    # Create a new SQL Connection to the server and the Webstraining DB
    $SQLConnection=New-Object System.Data.SqlClient.SqlConnection
    $SQLConnection.ConnectionString='Server=XXXXX\XXXXX;Database=WebTraining;Integrated Security=True'

    # Open the SQL Connection
    $SQLConnection.Open()

    # Create a new SQL Command with type "Stored Procedure"
    $SQLCmd=New-Object System.Data.SqlClient.SqlCommand
    $SQLCmd.CommandType=[System.Data.CommandType]::StoredProcedure

    # Set the command's text to the stored procedure
    $SQLCmd.CommandText='orc.get_Pers_Training_Disable_Accounts'

    # Point the command to the SQL Connection
    $SQLCmd.Connection=$SQLConnection

    # Create a new SQL Adapter and set it's SelectCommand to the previously create command variable.
    $SQLAdapter=New-Object System.Data.SqlClient.SqlDataAdapter
    $SQLAdapter.SelectCommand=$SQLCmd

    # Create a New Data set and fill it from the Adapter
    $DataSet=New-Object System.Data.DataSet
    $SQLAdapter.Fill($DataSet)

    # Select the first column of the first column of the first table which SHOULD be the usernames then iterate through substrings to remove the domain from the username. ("DOMAIN\Username" becomes "Username")
    $Usernames = (Select-Object -InputObject $DataSet.Tables[0].nt_username -Index 0) | ForEach-Object { $_.substring($_.indexof('\')+1)}

    # Output the file to the location set in the Configuration block of this script
    $Usernames | Out-File -FilePath $LockOutListFile

    # Close the connection to the SQL Database
    $SQLConnection.Close()
}

#========================================================================================================================
#                                                     LOG CREATION                                                      #
#========================================================================================================================

# Function to write log data to the main script log
function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Data)
        
        try{
            # Create a TimeStamp for Log inputs
            $TimeStamp = (get-date).toshortdatestring() + " " + (get-date).tolongtimestring()
            
            # Test if output directory exists; Create if not.
            if(-not(test-path $LogFileBasePath)){
                New-Item -path $LogFileBasePath -ItemType Directory
            }

            # Append Data to MAIN Log File
            "[$TimeStamp] [$($env:COMPUTERNAME)] $Data" | Out-File $LogFileALL -Encoding ascii -Append
        }
        catch{
            # On fail, attempt to append error
            Write-Log "Failed to write to log file"
        }
}

# Function to write log data to the VIP script log
function Write-LogVIP {
    param([Parameter(Mandatory=$true)][string]$Data)
        
        try{
            # Create a TimeStamp for Log inputs
            $TimeStamp = (get-date).toshortdatestring() + " " + (get-date).tolongtimestring()
            
            # Test if output directory exists; Create if not.
            if(-not(test-path $LogFileBasePath)){
                New-Item -path $LogFileBasePath -ItemType Directory
            } 
                       
            # Append Data to VIP Log File
            "[$TimeStamp] [$($env:COMPUTERNAME)] $Data" | Out-File $LogFileVIP -Encoding ascii -Append
        }
        catch{
            # On fail, attempt to append error to Main log
            Write-Log "Unable to write to log file"
        }
}

# Function to write log data to the EXEMPT script log
function Write-LogEXEMPT {
    param([Parameter(Mandatory=$true)][string]$Data)
        
        try{
            # Create a TimeStamp for Log inputs
            $TimeStamp = (get-date).toshortdatestring() + " " + (get-date).tolongtimestring()

            # Test if output directory exists; Create if not.
            if(-not(test-path $LogFileBasePath)){
                New-Item -path $LogFileBasePath -ItemType Directory
            }
                        
            # Append Data to EXEMPT Log File
            "[$TimeStamp] [$($env:COMPUTERNAME)] $Data" | Out-File $LogFileExempt -Encoding ascii -Append
        }
        catch{
            # On fail, attempt to append error to Main log
            Write-Log "Unable to write to log file"
        }
}

#========================================================================================================================
#                                                    ACTIVE DIRECTORY                                                   #
#========================================================================================================================

# Function to perform disable action on user account and set AD description.
function WAM-Disable{
    param([Parameter(Mandatory=$True)][string]$Identity)
        
        # Checks to see if script is set to only generate a report.  $ReportOnly -eq $True will generate all log files, but will NOT disable accounts.
        if ($ReportOnly -ne $True){
            
            try{
                # Disable the user account
                Disable-ADAccount -Identity $Identity

                # Capture Old Description and append not that account was disabled for training non-compliance.
                $OldDescription = (Get-ADUser -Identity $Identity -Properties Description).Description
                Set-ADUser -Identity $Identity -Description "$OldDescription, (Account disabled for training non-compliance on $((get-date).toshortdatestring())."

                # If Try block is successfull, set the below variable to false so that log output occurs in Finally block.
                $Error = $False
            }
            
            catch{
                # In the event of a failure, append it to the main log.
                Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Failed to Disable Account."

                # If user is a VIP user, also write to the VIP log.
                if($ADAccount.DistinguishedName -like "*VIP"){
                    Write-LogVIP "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Failed to Disable Account."
                }

                # If a terminating error is caught, set the $Error variable to $True to skip log output in Finally block as the error is also logged in the Catch block.
                $Error = $True
            }

            finally{
                
                # Only run this block if Try block is successful
                if ($Error -eq $False){
                    
                    # Append main log with information on disablement
                    Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account Disabled."

                    
                    # If user is a VIP user, also write to the VIP log.
                    if($ADAccount.DistinguishedName -like "*VIP"){
                        Write-LogVIP "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account Disabled."
                    }
                }
            }
        }

        # Only including Else block so that you still generate a complete log during a $ReportOnly -eq $True scenario.
        Else{
            # Append main log with information on disablement
            Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account Disabled."

            # If user is a VIP user, also write to the VIP log.
            if($ADAccount.DistinguishedName -like "*VIP"){
                Write-LogVIP "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account Disabled."
            }
        }
}

# Function to check list of non-compliant users for exemptions and then disable remaining in AD.
function WAM-ADSearch{
    # Imports the username list created from function: WAM-SQLLookup
    $LockOutList = Get-Content -Path $LockOutListFile

    foreach ($User in $LockOutList){
        # Try/Catch to see if identified usernames exist in AD.
        try{
            # Console output for display when debugging script
            Write-Host "Searching for $User in Active Directory"

            # Set a variable containing the user account properties required for checks and logs.
            $ADAccount = Get-ADUser -Identity $User -Properties Department, OfficePhone, whenCreated, MemberOf
        }
        catch{
            # Console output for display when debugging script
            Write-Host "$User not found in Active Directory" -ForegroundColor red
        }

        # $ADAccount will be $Null if the above Try/Catch did NOT find an account in AD.
        if ($Null -ne $ADAccount){
            
            # Check if the account is enabled.  If already disabled skip to log entry in else statement.
            if ($ADAccount.enabled -eq $True){
                
                # Check to see ensure that the user is not within their grace period.  If they are skip to log entry in else statement.
                if (($ADAccount.whenCreated.AddDays($GracePeriod)) -lt (get-date)){
                    
                    # Set variable containing a list of the AD groups that the user is a member of.
                    # This is needed to check if the user is in an exempt group further down.  Placed here because it would be unnecessary to do this pull for users who have no chance of being disabled.
                    $ADgroups = (Get-ADUser $ADAccount -Properties memberof) | select -ExpandProperty memberof | ForEach-Object {(Get-ADGroup $_).name}

                    # Check to see if REL users are currently exempt from WAM training.  If $REL is set to $True in the Configuration Variables, this block will move REL users past the disablement block.
                    if (($REL -eq $True) -AND ($ADAccount.DistinguishedName -like "*OU=REL*")){
                        
                        # Write user information to main log and to the EXEMPT log.
                        Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), REL Users are currently exempt from WAM Training."
                        Write-LogEXEMPT "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), REL Users are currently exempt from WAM Training."
                    }
                        # If user is NOT a REL user OR REL users are not currently exempt, check if VIP users are currently exempt.  If $VIP is set to $True in the Configuration Variables, this block will move VIP users past the disablement block.
                        elseif(($VIP -eq $True) -AND ($ADAccount.DistinguishedName -like "*OU=VIP*")){

                            # Write user information to main log and EXEMPT log.
                            Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), VIP Users are currently exempt from WAM Training."
                            Write-LogVIP "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), VIP Users are currently exempt from WAM Training."
                            Write-LogEXEMPT "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), VIP Users are currently exempt from WAM Training."
                        }

                        # If user is NOT a VIP user OR VIP users are not currently exempt, check if SCO users are currently exempt.  If $SCO is set to $True in the Configuration Variables, this block will move SCO users past the disablement block.
                        elseif(($SCO -eq $True) -AND ($ADAccount.DistinguishedName -like "*OU=SCO*")){

                            # Write user information to main log and EXEMPT log.
                            Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), SCO Users are currently exempt from WAM Training."
                            Write-LogEXEMPT "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), SCO Users are currently exempt from WAM Training."
                        }


                        # If user is NOT a VIP user OR VIP users are not currently exempt, check if user is a member of one of the AD groups that grant exemption.  
                        # If user is a member of one of the groups, this block will move them past the disablement block.
                        elseif($null -ne ($Exempt | Where-Object {$ADgroups -match $_})){
                            
                            # Write user information to main log and EXEMPT log.
                            Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), User is a member of an exemption group in AD."
                            Write-LogEXEMPT "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), User is a member of an exemption group in AD."
                        }

                        # If user does not meet any of the requirements above for exemption, proceed to disablement block.
                        else{
                            
                            # Disable user
                            WAM-Disable $User                            
                        }
                }

                else{
                    
                    # If the user has been at the company for less time than the defined grace period, append a log entry that the user recently entered the company.
                    Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account is less than $GracePeriod days old."
                    Write-LogEXEMPT "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account is less than $GracePeriod days old."
                }
            }

            else{
                
                # If the 'Enabled' attribute is $false, append a log entry that account is already disabled and skip the exemption checks and disablement.
                Write-Log "$User, $($ADAccount.Name), $($ADAccount.Department), $($ADAccount.OfficePhone), Account is already disabled."
            }
        
        }
        
    }


}

#========================================================================================================================
#                                                    Sequentialization                                                  #
#========================================================================================================================

function Start-Main {
    # Write 'BEGIN' line for script logs.
    Write-Log -Data "********************BEGIN - WAM Training Non-Compliance Lockout - ALL********************"
    Write-LogVIP -Data "********************BEGIN - WAM Training Non-Compliance Lockout - VIP********************"
    Write-LogEXEMPT -Data "********************BEGIN - WAM Training Non-Compliance Lockout - EXEMPT********************"

    # Call function to generate list of non-compliant users.
    WAM-SQLLookup

    # Call function to check exemptions and disable accounts.
    WAM-ADSearch

    # Write 'END' line for script logs.
    Write-Log -Data "********************END - WAM Training Non-Compliance Lockout - ALL********************"
    Write-LogVIP -Data "********************END - WAM Training Non-Compliance Lockout - VIP********************"
    Write-LogEXEMPT -Data "********************END - WAM Training Non-Compliance Lockout - EXEMPT********************"
}

#========================================================================================================================
#                                                     Initialization                                                    #
#========================================================================================================================

# Start the Script
Start-Main
