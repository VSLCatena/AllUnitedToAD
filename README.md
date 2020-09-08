# AllUnitedToAD
Powershell script to convert export from membership administration to Active Directory

<Hr>
 AUTHOR  : Martijn Koetsier

 Based on: Marius / Hican - http://www.hican.nl - @hicannl (26-04-2012 --> 07-08-2014)

 DATE    : 2020-07-29

 EDIT    : 

 COMMENT : This script creates new Active Directory users,
           including different kind of properties, based
           on an .csv-file.

 VERSION : 1.0.5


# Changelog

- 0.9.0      : 2019-03-17 Copied code
- 0.9.1    : 2019-04-06 Removed attributes not used 
- 0.9.2    : 2019-04-13 Create username and set functions
- 0.9.3    : 2019-04-20 Included Simulation argument
- 0.9.4    : 2019-04-28 working concept and user to contact idea worked out
- 0.9.5    : 2019-06-16 Move Home & profile and edit in user object when lid af
- 0.9.6    : 2019-07-09 Error with duplicate username loop. Fixed by initializing sam_ori. Fixed extra log in output folder
- 1.0.0    : 2020-07-02 Change primary key and optimized functions. Created backup
- 1.0.1    : 2020-07-03 Added additional info when change of fields is performed, added https://lazywinadmin.com/2015/05/powershell-remove-diacritics-accents.html method2
- 1.0.2 	: 2020-07-03 Fix for encoding. omit -Encoding --> UTF8, -Encoding Default --> do nothing https://stackoverflow.com/questions/48947151/import-csv-export-csv-with-german-umlauts-%C3%A4-%C3%B6-%C3%BC
- 1.0.3 	: 2020-07-17 Added mailnickname for azure
- 1.0.4 	: 2020-07-28 Fix for phone numbers
- 1.0.5 	: 2020-07-29 Update fix for more numbers and debug
- 1.0.5a    : 2020-08-06 Created generalized version for GitHub
- 1.0.6   : 2020-09-08 Validation of email fixed

# Requirements
- Domain Controller
  - Active Directory
  - Powershell
  - Domain Account
    - Account Operator rights (optional: Logon as batch script rights when using scheduled task)
    - Right to write in script folder (for logs, backups and input folder)
  - Share for input files (Please use FSRM with quota and screening)

- AllUnited as membership administration program

# Usage

## Fill variables in script

- \$TargetOU = "OU=A,OU=B,OU=C"
  - New users are placed here
- \$disabledOU ="OU=A,OU=B,OU=C,$addn"
  - Old users are placed here
- \$contactOU = "OU=A,OU=B,OU=C,$addn"
  - Contacts (WIP) are placed here
- \$TargetGroup ="CN=D,OU=A,OU=B,OU=C,$addn" 
  - Group added ánd removed from users when created / removed/disabled

Sync keys of csv and AD are needed to find unique account. This is performed using the relationshipnumber of Allunited that will be written to the attriubte employeeID

- \$primaryKeyCSV = "contactid" 
- \$primaryKeyAD = "employeeID" 
- \$changeThreshold = 0.25
  - If a change of more than 25% is going to happen, the stop the scirpt.

- \$homeDrive = "H"
- \$homeDirectory = "\\$dnsroot\DFS\Homes\"
- \$profilePath =  "\\$dnsroot\DFS\Profiles\"
- \#\$homeDirectory_direct = "F:\Homes" #WIP
- \#\$profilePath_direct = "F:\Profiles" #WIP



## Start script using start.bat:
- powershell.exe {Location to files}\AllUnitedToAD\SyncAllUnitedAD.ps1 -simulation:\$false -interactive:\$false