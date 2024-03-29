# PSScriptAnalyzer - ignore creation of a SecureString using plain text (due to random generation) and ignore StateChangingFunctions. GlobalVars are currently a workaround.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "")]
[CmdletBinding()]
Param(
    $simulation = $True,
    $interactive = $True
)
###########################################################
# AUTHOR  : Martijn Koetsier
# Based on: Marius / Hican - http://www.hican.nl - @hicannl (26-04-2012 --> 07-08-2014)
# DATE    : 2019-04-06
# COMMENT : This script creates new Active Directory users,
#           including different kind of properties, based
#           on a CSV-file.
# VERSION : 1.3.0
###########################################################
#
# Changelog
#
###########################################################

# 0.9      : 2019-03-17 Copied code
# 0.9.1    : 2019-04-06 Removed attributes not used
# 0.9.2    : 2019-04-13 Create username and set functions
# 0.9.3    : 2019-04-20 Included Simulation argument
# 0.9.4    : 2019-04-28 working concept and user to contact idea worked out
# 0.9.5    : 2019-06-16 Move Home & profile and edit in user object when lid af
# 0.9.6    : 2019-07-09 Error with duplicate username loop. Fixed by initializing sam_ori. Fixed extra log in output folder
# 1.0.0    : 2020-07-02 Change primary key and optimized functions. Created backup
# 1.0.1    : 2020-07-03 Added additional info when change of fields is performed, added https://lazywinadmin.com/2015/05/powershell-remove-diacritics-accents.html method2
# 1.0.2    : 2020-07-03 Fix for encoding. omit -Encoding --> UTF8, -Encoding Default --> do nothing https://stackoverflow.com/questions/48947151/import-csv-export-csv-with-german-umlauts-%C3%A4-%C3%B6-%C3%BC
# 1.0.3    : 2020-07-17 Added mailnickname for azure
# 1.0.4    : 2020-07-28 Fix for phone numbers
# 1.0.5    : 2020-07-29 Update fix for more numbers and debug
# 1.0.5a   : 2020-08-06 Created generalized version for GitHub (not this one!)
# 1.0.6    : 2020-09-08 Validation of email fixed
# 1.0.7    : 2020-09-23 last check of contact creation for old members
# 1.0.8	   : 2021-06-12 keep input logs for longer time
# 1.0.9	   : 2021-08-01 Fix officephone for change-users set

# 1.0.10   : 2021-10-31 Disable profilepath
# 1.0.10   : 2022-01-18 Fix homedrive bug due to commented profilepath +  import with utf8
# 1.0.11   : 2022-02-10 Exclude users without valid name2
# 1.0.12   : 2022-02-10 Rename lid-af users to $samaccountname
# 1.0.13   : 2022-07-29 fix new header, line 203

# 1.1.0    : 2021-10-01 Rewrite / cleanup code, so Github and local are identical
# 1.1.1    : 2021-10-04 Add secondary email

# 1.2.0    : 2022-12-02 Rewrite / cleanup
# 1.2.1    : 2022-12-04 Fix PSScriptanalyser stuff
# 1.3.0    : 2023-12-02 Fix issues with paths and DNS Suffix


# ERROR REPORTING ALL
Set-StrictMode -Version latest

#----------------------------------------------------------
# LOAD ASSEMBLIES AND MODULES
#----------------------------------------------------------

Try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
Catch {
    Write-Data2Log "error" "ActiveDirectory Module couldn't be loaded. Script will stop!"
    Exit 1
}


#----------------------------------------------------------
# LOAD STATIC VARIABLES
#----------------------------------------------------------

function Initialize-StaticVar() {
    New-Variable -Scope global -Option ReadOnly, AllScope -Name path -Value $(if ($PSScriptRoot -ne "") { $PSScriptRoot } else { $(Get-Location).Path })
    New-Variable -Scope global -Option ReadOnly, AllScope -Name date -Value $(Get-Date)
    New-Variable -Scope global -Option Constant, AllScope -Name ADdn -Value $((Get-ADDomain).DistinguishedName)
    New-Variable -Scope global -Option Constant, AllScope -Name UPNSuffix -Value $((Get-ADForest).UPNsuffixes[0])
    New-Variable -Scope global -Option ReadOnly, AllScope -Name BackupAD -Value $(Join-Path $path "\\backup\\AD_Backup-$(Get-Date -Format 'yyyy-MM-dd').csv")
    New-Variable -Scope global -Option ReadOnly, AllScope -Name BackupInput -Value $(Join-Path $path "\\backup\\Input_Backup-$(Get-Date -Format 'yyyy-MM-dd').csv")
    New-Variable -Scope global -Option ReadOnly, AllScope -Name LogFile -Value $(Join-Path $path "\\log\\$(Get-Date -Format "yyyy-MM-dd").log")
}

#----------------------------------------------------------
# LOAD Environment configuration
#----------------------------------------------------------

<# ADHeaderData
ChangeThreshold
ContactOU
DisabledOU
Enabled
Expires
CSVHeaderData
HomeDirectory
HomeDirectory_Direct
HomeDrive
InactiveDays
LogRetentionDays
PrimaryKeyAD
PrimaryKeyCSV
ProfilePath
ProfilePath_Direct
TargetDefaultGroups
TargetOU

new variable/scope
Global - Variables created in the global scope are accessible everywhere in a PowerShell process.
Local - The local scope refers to the current scope, this can be any scope depending on the context.
Script - Variables created in the script scope are accessible only within the script file or module they are created in.
Private - Variables created in the private scope cannot be accessed outside the scope they exist in. You can use private scope to create a private version of an item with the same name in another scope.
A number relative to the current scope (0 through the number of scopes, where 0 is the current scope, 1 is its parent, 2 the parent of the parent scope, and so on). Negative numbers cannot be used.
Local is the default scope when the scope parameter is not specified.

new variable/option
None - Sets no options. None is the default.
ReadOnly - Can be deleted. Cannot be changed, except by using the Force parameter.
Private - The variable is available only in the current scope.
AllScope - The variable is copied to any new scopes that are created.
Constant - Cannot be deleted or changed. Constant is valid only when you are creating a variable. You cannot change the options of an existing variable to Constant.
#>

function Import-Config() {
    if (Test-Path -Path $path\.env) {
        $options = Get-Content -Path $path\.env | ConvertFrom-Json
        foreach ($opt in $options) {
            New-Variable -Name $opt.name -Value $opt.value -Scope $opt.scope -Option $opt.option -Description $opt.description
        }
    }
    else {
        Write-Data2Log "error" ".env not found. Script will stop!"
        Exit 1
    }
}





#----------------------------------------------------------
#START FUNCTIONS
#----------------------------------------------------------

Function invoke-SyncAllUnitedToAD {
    <#
    .DESCRIPTION
    The main script that is used to manipulate the environment

    .INPUTS
    None.

    .OUTPUTS
    None.

    .EXAMPLE
    PS> invoke-SyncAllUnitedToAD
    #>
    Write-Data2Log "info" "STARTED SCRIPT" -disableWrite:$true
    Write-Data2Log "warning" "Status of simulation: $Simulation" -disableWrite:$true
    Get-CSVUserDataset
    Get-ADUserDataset
    if ([math]::Abs($($global:users_CSV).Length - $($global:users_AD).Length) / $($global:users_AD).Length -ge $changeThreshold ) {
        Write-Data2Log "warning" "Change in users is over $changeThreshold. Due to safety reasons, this script will stop."
        if (!$($interactive)) { exit 1 }
    }
    Get-SetResult
    if ($interactive) { Read-Host("Continue?") }
    Add-User
    Set-User
    Move-User

    #Clean-Users

}

Function Write-Data2Log{
    Param(
        $loglevel="INFO",
        $data="",
        $disableWrite=$false
    )
    $oldWIpref = $WhatIfPreference
    $WhatIfPreference = $false
    $timestamp = $(get-date -Format "yyyy-MM-dd HHmmss")
    $stack = (Get-PSCallStack | select -skip 1 -first 1)
    $StackString = "[$($stack.FunctionName)[$($stack.Scriptlinenumber)]"

    $full = "$timestamp ["+"$loglevel".ToUpper()+ "]`t`t$stackString`t$data"
    write-host($full)
    if($disableWrite -ne $true){
        $full | Out-File $LogFile -append
        }
    $WhatIfPreference = $oldWIpref
}

Function Get-filteredDataset {
    param(
        [object]$dataset,
        [object]$set = @(),
        [string]$key
    )
    <#
    .DESCRIPTION
    Compares an array of objects (with $key as key) against list of keys ($set) and returns objects that are intersecting.

    .PARAMETER dataset
    Specifies the main dataset

    .PARAMETER set
    Specifies a certain subset of the main dataset with values corresponding to $key

    .PARAMETER key
    Specifies primary key on which the comparison must be done
    .INPUTS
    None.

    .OUTPUTS
    filteredDataset

    .EXAMPLE
    PS> Get-filteredDataset $users_CSV $set_edit $primaryKeyCSV

    #>
    $dataset_size = @($dataset).length
    $set_size = @($set).length
    Write-Data2Log "info" "There are $dataset_size items that are validated against $set_size"
    # filter dataset with list



    $filteredDataset = @()
    $dataset | ForEach-Object {
        $data = $_
        $set | ForEach-Object {
            $item = $_
            if ($data.$($key) -eq $item) {
                $filteredDataset += $data
            }
        }
    }
    return $filteredDataset
}

Function Get-ADUserDataset {
    <#
    .DESCRIPTION
    Retrieves all the users from AD with some specific boundaries

    .INPUTS
    None.

    .OUTPUTS
    File. Exports to local disk for backup
    $global:users_AD containing all the data

    .EXAMPLE
    PS>  Get-ADUserDataset

    #>
    $global:users_AD = Get-ADUser -Filter * -Properties  $($global:ADHeaderData.split(";")) -ResultSetSize $null -SearchBase $TargetOU
    $global:users_AD | Export-Csv -Path $BackupAD -Delimiter ";"
    Write-Data2Log "info" "Created backup of all Users/Leden"
    Write-Data2Log "info" "There are $(@($users_AD).Length) users in AD"
    Write-Data2Log "info" "Status phonenumbers: `n$($global:users_AD | Select-Object -ExpandProperty telephoneNumber | Group-Object length | Format-Table | Out-String )"

}

Function Get-CSVUserDataset {
    <#
    .DESCRIPTION
    Gets the CSV-data from file

    .INPUTS
    None.

    .OUTPUTS
    $global:users_CSV containing all the data

    .EXAMPLE
    PS> Get-CSVUserDataset

    #>
    $global:csvfile = Get-ChildItem $path/input/*.csv | Sort-Object LastWriteTime | Select-Object -ExpandProperty Name -Last 1
    if ("$csvfile".Length -eq 0) {
        Write-Data2Log "info" "No CSV-file found. Script will stop!" -disableWrite:$true
        exit 1
    }
    $global:users_CSVRAW = Import-Csv -Delimiter ';' -Encoding UTF8 -Path "$path/input/$csvfile" -Verbose

    $global:users_CSV = $global:users_CSVRAW | Where-Object { $_.Naam -ne "" }
    $global:users_CSVInvalid = $global:users_CSVRAW | Where-Object { $_.Naam -eq "" }
    Write-Data2Log "info" "There are $(@($users_CSVRAW).length) users in AllUnited (excluding $(@($users_CSVInvalid).length) with invalid name)"
}

Function Get-SetResult {
    <#
    .DESCRIPTION
    Uses set functions (external) to get from two dataset the intersect, left and right values. Intersect is in both sets, left only in left set and right only in right set.

    .INPUTS
    $users_CSV
    $users_AD

    .OUTPUTS
    Three sets: intersect, left and right

    .EXAMPLE
    PS> Get-SetResult

    #>

    $temp_set_AD = $users_AD | ForEach-Object { $_.$primaryKeyAD } #get column of AD field
    New-Variable -Name set_AD -Value ($temp_set_AD | Sort-Object -Unique) #get only unique values
    Write-Data2Log "warning" "There are $(@($set_AD).length) users with unique LIDNUMMER in AD"

    $temp_set_CSV = $users_CSV | ForEach-Object { $_.$primaryKeyCSV } #get column of CSV field
    New-Variable -Name set_CSV -Value ($temp_set_CSV | Sort-Object -Unique) #get only unique values
    Write-Data2Log "warning" "There are $(@($set_CSV).length) users with unique LIDNUMMER in AllUnited"


    $set_edit = Get-SetOperationResult -Left $set_AD -Right $set_CSV -OperationType Intersection
    $set_move = Get-SetOperationResult -Left $set_AD -Right $set_CSV -OperationType Difference-LeftMinusRight
    $set_create = Get-SetOperationResult -Left $set_AD -Right $set_CSV -OperationType Difference-RightMinusLeft

    Write-Data2Log "info" "All users from AD $(@($set_AD).Length) - $(@($set_move).length) Remove + $(@($set_create).length) Create = $(@($set_edit).length) edit. Cross checking every set with AD / CSV:"

    $global:usersEdit   = Get-filteredDataset -dataset $users_CSV -set $set_edit   -key $primaryKeyCSV
    $global:usersMove   = Get-filteredDataset -dataset $users_AD  -set $set_move   -key $primaryKeyAD
    $global:usersCreate = Get-filteredDataset -dataset $users_CSV -set $set_create -key $primaryKeyCSV

    Write-Data2Log "warning" "There are $(@($global:usersEdit).length) users in AD eligable for edit."
    Write-Data2Log "warning" "There are $(@($global:usersMove).length) users to be disabled"
    $list_name = $global:usersMove | Select-Object -ExpandProperty displayName | Sort-Object  #because list of DN
    $list_name = $list_name -join "`n" | Out-String
    Write-Data2Log "info" "Disabled users:`n$list_name"
    Write-Data2Log "warning" "There are $(@($global:usersCreate).length) users to be created from AllUnited"

    $list_name = $global:usersCreate | Select-Object -ExpandProperty Naam | Sort-Object
    $list_name = $list_name -join "`n" | Out-String

    Write-Data2Log "info" "To be created users:`n$list_name"
}

Function get-username {
    param(
        [boolean]$new,
        [string]$firstname,
        [string]$prelastname,
        [string]$lastname
    )
    <#
    .DESCRIPTION
    Creates username based on name, prelastname and lastname and removes weird chars

    .PARAMETER new
    Boolean, if this is for a completely new user

    .PARAMETER firstname
    Firstname string

    .PARAMETER prelastname
    Letters between first and last name

    .PARAMETER lastname
    Lastname String

    .INPUTS
    None.

    .OUTPUTS
    System.String. New usersname

    .EXAMPLE
    PS> get-username $true $givenname $pre $lastname

    #>
    $j = 0
    $sam_ori = $null
    $p_lastname = $prelastname.ToLower() + $lastname.ToLower()
    $p_lastname = $p_lastname.Replace(",", "")
    $p_lastname = $p_lastname.Replace(".", "")
    $p_lastname = $p_lastname.Replace(" ", "")
    $p_lastname = $p_lastname.Replace("'", "")
    $p_lastname = $p_lastname.Replace("-", "")

    $fullname = $firstname.substring(0, 1).ToLower() + $p_lastname

    If ($fullname.length -ge 20) {
        $fullname = $fullname.substring(0, 20)
    }
    $k = $true
    $sam = $fullname

    while ($k -eq $true) {
        Try { $exists = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -Properties useraccountcontrol }
        Catch { Write-Warning "$sam could not be found.." } #if not found,gives error
        If ($exists) {
            if ($new) {
                Write-Data2Log "warning" "$sam already exist"
                if (!$sam_ori) { $sam_ori = $sam }
                $j = $j + 1
                $sam = $sam_ori + $j
            }
            if (!$new) {
                $k = $false
                return($sam)
            }
        }
        If (!$exists) {
            Write-Data2Log "info" "$sam is new username"
            $k = $false
            return($sam)
        }
    }
}

function Optimize-phonenumber($no) {
    <#
    .DESCRIPTION
    #Count Name                      Group
    #----- ----                      -----
    #  895 10                        {0612345678...}
    #    2 13                        {0035712345678, 0013012345678}
    #    4 14                        {00441234567891}
    #    3 9                         {061234567 }
    #    2 11                        {03212345679}
    #    4 12                        {031612345678, 040123456789, 031687654321}
    #    1 15                        {004912345678901}
    .PARAMETER Number
    A phone number

    .INPUTS
    None.

    .OUTPUTS
    System.String. Optimized phone number

    .EXAMPLE
    PS> Optimize-phonenumber -no 0612345678
    +31612345678
    #>

    $type = $null
    $result = @()
    $var = [string]$no
    $var = $var.trim() #remove spaces
    $len = $var.Length
    #number can be between 8-15 digits. https://en.wikipedia.org/wiki/E.164
    If ($len -eq 10) { #10=perfect 0612345678 071 1234567
        $type = $null
        $res = $var -replace '^0', '+31'
    }

    Else { #wtf
        $res = $var
        $type = "No_Change_$len"

        #If ($($var -replace '^0+', '').Substring(0,1) -eq '6')
        #{
        #    #possible mobile phone number
        #    $type = "check Mob PhoneNo:$len"
        #    $res="+31$($var -replace '^0+', '')"
        #}
        #Else {
        #    $type = "check PhoneNo:$len"
        #    $res="+$($var -replace '^0+', '')"
        #}
    }


    $result += [PSCustomObject] @{
        Number = $res;
        Type   = $type;
    }
    return $result


}

function Remove-StringLatinCharacter {
    PARAM (
        [string]$String
    )
    <#
    .DESCRIPTION

    .PARAMETER String
    Specifies the String

    .INPUTS
    None.

    .OUTPUTS
    System.String. Removed weird symbols from name

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
}

function set-ADParameter {
    param(
        [string]$parameter
    )
    <#
    .DESCRIPTION
    retrieves parameter from object and updates it with new. Change is stored in update string
    .PARAMETER parameter
    retrieves AD parameter

    .INPUTS
    OfficePhone

    .OUTPUTS


    .EXAMPLE
    OfficePhone
        if(($userAD.OfficePhone -ne $OfficePhone) -and ($OfficePhone.length -gt 0)){
        $userAD.OfficePhone = $OfficePhone
        $update+="Phone[$OfficePhone_old => $OfficePhone],"
        }
    #>
    $var = Get-Variable $parameter #OfficePhone = 0612345678 (csv)
    $var_old = New-Variable -PassThru -Name "$((Get-Variable $var.name).Name)_old" -Value $global:userAD[$var.name]  #OfficePhone_old=06987654321
    if (($userAD[$var.name] -ne $var.value) -and ($var.value -gt 0)) {
        $global:userAD[$var.name] = $var.value
        $global:update += "$key[$value_old => $($var.value)],"
    }


}

Function Add-User {
    <#
    .DESCRIPTION
     Create user in AD based on global:usersCreate

    .INPUTS
    None.

    .OUTPUTS
    New AD User

    .EXAMPLE
    PS> Add-User

    #>

    $i = 0
    $global:usersCreate | ForEach-Object {

        $EmployeeID = $_.Relatienummer
        $DisplayName = Remove-StringLatinCharacter($_.Naam)
        $lastname = Remove-StringLatinCharacter($_.Achternaam)
        $initials = Remove-StringLatinCharacter((($_.Voorletters).replace(".", "")).replace(" ", ""))
        $pre = Remove-StringLatinCharacter($_.Tussenvoegsel)
        $GivenName = Remove-StringLatinCharacter($_.Voornaam)
        $Phone = $($_.Mobiel).replace("-", "")
        $Phone = $(Optimize-phonenumber($Phone)).Number
        $EmailAddress = ($_.Email).trim()
        $Description = $_.Lidnummer
        $Employeenumber = $_.Lidnummer
        if($_.GoogleAccount -ne $null) { $ExtensionAttribute2=$_.GoogleAccount } else { $ExtensionAttribute2=$null}
        $enabled = $true

        $password = ([char[]]([char]32..[char]122) | Sort-Object { Get-Random })[0..50] -join ''

        #(([char[]]([char]65..[char]90)+[char[]]([char]97..[char]121)+[char[]]([char]48..[char]57) | sort {Get-Random})[0..50] -join ''



        If (($displayName -eq "") -Or ($GivenName -eq "") -Or ($LastName -eq "")) {
            Write-Data2Log "error" "Please provide valid Full Name, GivenName and LastName. Processing skipped for user $($i): $($displayName), $($Description)."
        }
        Else { # Valid Full, given, lastname

            #$location = $TargetOU + ",$($addn)"  # Set the target OU
            $location = $TargetOU  # Set the target OU
            $sam = get-username -new $true -firstname $givenname -prelastname $pre -lastname $lastname
            Try {
                $exists = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -ErrorVariable e # get any user with saameacocuntanem,
                $exists = Get-ADUser -LDAPFilter "(Description= $Description)" -ErrorVariable e #get any user with specific description, possibly not needed after checking SetFunctions
                $exists = Get-ADUser -LDAPFilter "(employeeID=$employeeID)" -ErrorVariable e #get anny user with specific employeeID, possibly not needed after checking SetFunctions
            } #does samaccountname exist?
            Catch { Write-Warning "$e"  }
            If (!$exists) { #does not exist
                # Set all variables according to the table names in the Excel
                # sheet / import CSV. The names can differ in every project, but
                # if the names change, make sure to change it below as well.
                $setpass = ConvertTo-SecureString -AsPlainText $password -Force

                $OtherAttributes = @{mailnickname = $sam}
                if($extensionAttribute2 -ne $null){ $OtherAttributes += @{ExtensionAttribute2 = $extensionAttribute2 } }
                $splattedADUserproperties=@{
                         DisplayName = $DisplayName
                         GivenName = $GivenName
                         Initials = $initials
                         Surname = "$pre$lastname"
                         Description = $Description
                         EmailAddress = $EmailAddress
                         OfficePhone = $phone
                         UserPrincipalName = ($sam + '@' + $UPNSuffix)
                         EmployeeId = $EmployeeID
                         EmployeeNumber = $Employeenumber
                         AccountPassword = $setpass
                         HomeDirectory = "$HomeDirectory$sam"
                         HomeDrive = $homeDrive
                         Enabled = $enabled
                         OtherAttributes = $OtherAttributes
                }

                Try {
                    Write-Data2Log "info" "Creating user : $($sam)"
                    $WhatIfPreference = $simulation
                    New-ADUser $sam @splattedADUserproperties
                    # New-ADUser $sam -DisplayName $DisplayName `
                        # -GivenName $GivenName -Initials $initials -Surname $pre$lastname `
                        # -Description $Description -EmailAddress $EmailAddress -OfficePhone $phone `
                        # -UserPrincipalName ($sam + "@" + $UPNSuffix) `
                        # -EmployeeID $EmployeeID `
                        # -EmployeeNumber $Employeenumber `
                        # -AccountPassword $setpass `
                        # -HomeDirectory "$HomeDirectory$sam" `
                        # -HomeDrive $homeDrive -Enabled $enabled `
                        # -OtherAttributes @{mailnickname = $sam; extensionAttribute2 = $extensionAttribute2 }
                    $WhatIfPreference = $false

                    Write-Data2Log "info" "Created new user : $($sam)"

                    $dn = (Get-ADUser $sam).DistinguishedName

                    # Move the user to the OU ($location) you set above. If you don't
                    # want to move the user(s) and just create them in the global Users
                    # OU, comment the string below
                    If ([adsi]::Exists("LDAP://$($location)")) {
                        $WhatIfPreference = $simulation
                        Move-ADObject -Identity $dn -TargetPath $location
                        $WhatIfPreference = $false
                        Write-Data2Log "info" "User $sam moved to target OU : $($location)"

                    }
                    Else {
                        Write-Data2Log "error" "Targeted OU couldn't be found. Newly created user wasn't moved!"

                    }

                    # Rename the object to a good looking name (otherwise you see
                    # the 'ugly' shortened sAMAccountNames as a name in AD. This
                    # can't be set right away (as sAMAccountName) due to the 20
                    # character restriction
                    $newdn = (Get-ADUser $sam).DistinguishedName
                    $WhatIfPreference = $simulation
                    Rename-ADObject -Identity $newdn -NewName $DisplayName
                    Write-Data2Log "info" "Renamed $($sam) to $displayName."

                    foreach($TargetGroup in $TargetDefaultGroups){
                        Add-ADGroupMember -Identity "$TargetGroup" -Members $newdn
                        Write-Data2Log "info" "$sam was added to $TargetGroup"
                    }
                    $WhatIfPreference = $false



                }
                Catch {
                    Write-Data2Log "error" "Oops, something went wrong: $($_.Exception.Message)"
                }
            }
            Else {
                Write-Data2Log "error" "User $($sam) ($($GivenName) $($LastName)) already exists or returned an error!"

            }
        }
        $i++
    }
    Write-Data2Log "info" "$i users were created."
}

Function Set-User { #account both in AU and AD
    <#
    .DESCRIPTION
     Create user in AD based on global:usersCreate

    .INPUTS
    None.

    .OUTPUTS
    Modified AD User

    .EXAMPLE
    PS> Set-User

    #>
    $i = 1
    $global:usersEdit | ForEach-Object {
        $EmployeeID = $_.Relatienummer
        $DisplayName = Remove-StringLatinCharacter($_.Naam)
        $Surname = Remove-StringLatinCharacter($_.Achternaam)
        $Initials = Remove-StringLatinCharacter((($_.Voorletters).replace(".", "")).replace(" ", ""))
        $pre = Remove-StringLatinCharacter($_.Tussenvoegsel)
        $GivenName = Remove-StringLatinCharacter($_.Voornaam)
        $OfficePhone = $($_.Mobiel).replace("-", "")
        $OfficePhone = $(Optimize-phonenumber($OfficePhone)).Number
        $EmailAddress = ($_.Email).trim()
        $Description = $_.Lidnummer
        $EmployeeNumber = $_.Lidnummer
        $extensionAttribute2 = $_.GoogleAccount


        $userAD = Get-ADUser -LDAPFilter "($($primaryKeyAD)=$($_.$primarykeyCSV))" -Properties DistinguishedName, DisplayName, EmployeeID, Description, EmailAddress, OfficePhone, Initials, GivenName, Surname, Employeenumber, extensionAttribute2

        $EmailAddress_old = $userAD.EmailAddress
        $OfficePhone_old = $userAD.OfficePhone
        $EmployeeNumber_old = $userAD.EmployeeNumber
        $EmployeeID_old = $userAD.EmployeeID
        $Initials_old = $userAD.Initials
        $GivenName_old = $userAD.GivenName
        $Surname_old = $userAD.Surname
        $Description_old = $userAD.Description
        $DisplayName_old = $userAD.DisplayName
        $extensionAttribute2_old = $userAD.extensionAttribute2


        #security (2 out of 3 vars need to stay static)
        $test_disp = $userAD.Displayname -eq $displayName #equal displayname
        $test_eid = $userAD.EmployeeID -eq $EmployeeID #equal employeeid
        $test_desc = $userAD.Description -eq $description #equal description
        $test23 = $test_disp -and ($test_eid -or $test_desc) -or ($test_eid -and $test_desc); #2 out of 3 need to be true

        $update = ""
        if ($test23) {
            if (($userAD.EmailAddress -ne $EmailAddress) -and ($EmailAddress.length -gt 0)) { $userAD.EmailAddress = $EmailAddress; $update += "email[$EmailAddress_old => $EmailAddress]," }
            if (($userAD.OfficePhone -ne $OfficePhone) -and ($OfficePhone.length -gt 0)) { $userAD.OfficePhone = $OfficePhone; $update += "Phone[$OfficePhone_old => $OfficePhone]," }
            if (($userAD.EmployeeNumber -ne $EmployeeNumber) -and ($EmployeeNumber.length -gt 0)) { $userAD.Employeenumber = $EmployeeNumber; $update += "EmployeeNumber[$EmployeeNumber_old => $EmployeeNumber]," }
            if (($userAD.EmployeeID -ne $EmployeeID) -and ($EmployeeID.length -gt 0)) { $userAD.EmployeeID = $EmployeeID; $update += "EmployeeID[$EmployeeID_old => $EmployeeID]," }
            if (($userAD.Initials -ne $Initials) -and ($Initials.length -gt 0)) { $userAD.Initials = $Initials; $update += "Initials[$Initials_old => $Initials]," }
            if (($userAD.GivenName -ne $GivenName) -and ($GivenName.length -gt 0)) { $userAD.GivenName = $GivenName; $update += "GivenName[$GivenName_old => $GivenName]," }
            if (($userAD.Surname -ne $("$pre $Surname").trim()) -and ($("$pre $Surname").trim().length -gt 0)) { $userAD.Surname = $("$pre $Surname").trim(); $update += "Surname[$Surname_old => $Surname]," }
            if (($userAD.Description -ne $Description) -and ($Description.length -gt 0)) { $userAD.Description = $Description; $update += "Description[$Description_old => $Description]," }
            if (($userAD.DisplayName -ne $DisplayName) -and ($DisplayName.length -gt 0)) { $userAD.DisplayName = $DisplayName; $update += "DisplayName[$DisplayName_old => $DisplayName]," }
            if (($userAD.extensionAttribute2 -ne $extensionAttribute2) -and ($extensionAttribute2.length -gt 0)) { $userAD.extensionAttribute2 = $extensionAttribute2; $update += "Google Account[$extensionAttribute2_old => $extensionAttribute2]," }
        }

        #
        else {
            Write-Data2Log "info" "$DisplayName_old unable to update due too much desc/displayname/employeeid change"
        }

        if ($update.Length -gt 0) {
            $WhatIfPreference = $simulation
            Set-ADUser -Instance $userAD
            if ($userAD.Name -ne $DisplayName) {
                Write-Data2Log "Warning" "Name: $($userAD.Name) is not equal to DisplayName: $($DisplayName). Fixing this"
                Rename-ADObject -Identity $userAD.DistinguishedName -NewName $DisplayName
            }
            $WhatIfPreference = $false
            Write-Data2Log "info" "$DisplayName_old is updated with $update"
            $i++
        }

    }
    Write-Data2Log "info" "$i users were updated with new data."

}

Function Move-User {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    <#
    .DESCRIPTION
    Movement of user & data

    .INPUTS
    None.

    .OUTPUTS
    Modified AD Users

    .EXAMPLE
    PS> Move-User

    #>

    $i = 1
    $global:usersMove | ForEach-Object {
        $samaccountname = $_.sAMAccountName
        $user = $_.DistinguishedName
        if ($($_.displayName) -notin "$IgnoreUsersDisplayName") {

            $password = ([char[]]([char]32..[char]122) | Sort-Object { Get-Random })[0..50] -join ''
            $setpass = ConvertTo-SecureString -AsPlainText $password -Force
            $description = "Disabled_$(Get-Date -Format "yyyy-MM-dd")__$($_.description)"
            $WhatIfPreference = $simulation
            <#
        $targetHD="$homedirecory_direct\_old\$samaccountname"
        $targetPP="$profilepath_direct\_old\$samaccountname.?"


        Move-Item -Path "$homeDirectory_direct\$samaccountname" -Destination "$targetHD" -Force
        Move-Item -Path "$profilepath_direct\$samaccountname.?" -Destination "$targetPP" -Force #>

            #Set-ADUser -Identity $user -clear mail,telephoneNumber  -Enabled $False -Description $description -HomeDirectory "$homedirectory/_old/$samaccountname" -ProfilePath "$profilepath/_old/$samaccountname"
            Set-ADUser -Identity $user -Clear mail, telephoneNumber, extensionAttribute2 -Enabled $False -Description $description
            Set-ADAccountPassword -Identity $user -NewPassword $setpass -Reset
            foreach($TargetGroup in $TargetDefaultGroups){
                Remove-ADGroupMember -Identity $TargetGroup -Members $user -Confirm:$false
                Write-Data2Log "info" "$user was removed from $TargetGroup"
            }
            Move-ADObject -Identity $user -TargetPath $disabledOU
            # DN is invalid as user has moved but sam can be used
            Get-ADUser $samaccountname | Rename-ADObject -NewName $samaccountname
            Write-Data2Log "info" "$($_.name) is cleared and password randomized. Renamed to $samaccountname"
            $WhatIfPreference = $false
            $i++
        }
    }
    Write-Data2Log "info" "$i users have been disabled and moved."
}

function Clear-users {
    <#
    .DESCRIPTION
    Movement of user & data

    .INPUTS
    None.

    .OUTPUTS
    Removed AD User + Added contact

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    $userBase = Search-ADAccount -UsersOnly -SearchBase $disabledOU -AccountInactive -TimeSpan $inactiveDays | Where-Object { $_.enabled -ne $true }
    $userBaseDetail = $userBase | ForEach-Object { Get-ADUser -Identity $_.SamAccountName -Properties Name, sAMAccountName, description, employeeID, employeeNumber whenChanged, whenCreated | Select-Object Name, sAMAccountName, description, employeeID, Employeenumber, whenChanged, whenCreated }
    $userBaseDetail | ForEach-Object { New-ADObject -Name "$($_.Name) [$($_.description)]" -Type contact -Description $_.description -OtherAttributes @{'employeeID' = "$_.employeeID"; 'info' = "Relatienummer: $_.employeeID`nEmployeeNumber: $_.employeenumber`nWhenCreated: $_.whenCreated`nWhenChanged: $_.whenChanged" } -Path $contactOU }

    #$homeDriveRoot = "\server1userfolders"
    #$leaversRoot = "\server1userfoldersoldusers"

    # Get the list of folders in the home drive share
    #$folders = Get-ChildItem $homeDriveRoot | Select -ExpandProperty Name

    # Get the list of active users from AD
    #$activeUsers =  Get-ADUser -Filter {Enabled -eq $true} | Select -ExpandProperty SamAccountName

    # Compare the list of users to the list of folders
    #$differences = Compare-Object -ReferenceObject $activeUsers -DifferenceObject $folders | ? {$_.SideIndicator -eq "=>"} | Select -ExpandProperty InputObject

    # For each folder that shouldn't exist, move it
    #$differences | ForEach-Object {Move-Item -Path "$homeDriveRoot$_" -Destination "$leaversRoot$_" -Force}


}
function invoke-PostCleanUp() {
    $WhatIfPreference = $simulation
    $DatetoDelete = $Date.AddDays($LogRetentionDays)
    Get-ChildItem $path/input/*.log | Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item #delete logs older than 30 days
    Copy-Item "$path/input/$global:csvfile" -Destination $backupinput
    Remove-Item "$path/input/$global:csvfile"
    Write-Data2Log "info" "Removed CSV file"
    $WhatIfPreference = $false
    Write-Data2Log "info" "STOPPED SCRIPT"
    Copy-Item "$LogFile" -Destination "$path/input"
}

Initialize-StaticVar
Start-Transcript -path "$path/log/transcript_$(Get-Date -Format "yyyy-MM-dd").log"
Import-Config #import config
. "$path\\SetOperations.ps1" #dot source set-operations
Invoke-SyncAllUnitedToAD #the whole program
Invoke-PostCleanUp #cleanup and move files

Stop-Transcript