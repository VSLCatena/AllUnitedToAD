[CmdletBinding()]
Param(
    $simulation=$True,
    $interactive=$True
)
###########################################################
# AUTHOR  : Martijn Koetsier
# Based on: Marius / Hican - http://www.hican.nl - @hicannl (26-04-2012 --> 07-08-2014)
# DATE    : 2019-04-06
# EDIT    : 
# COMMENT : This script creates new Active Directory users,
#           including different kind of properties, based
#           on an input_create_ad_users.csv.
# VERSION : 1.0.5
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
# 1.0.2 	: 2020-07-03 Fix for encoding. omit -Encoding --> UTF8, -Encoding Default --> do nothing https://stackoverflow.com/questions/48947151/import-csv-export-csv-with-german-umlauts-%C3%A4-%C3%B6-%C3%BC
# 1.0.3 	: 2020-07-17 Added mailnickname for azure
# 1.0.4 	: 2020-07-28 Fix for phone numbers
# 1.0.5 	: 2020-07-29 Update fix for more numbers and debug
# 1.0.5a    : 2020-08-06 Created generalized version for GitHub
# 1.0.6   : 2020-09-08 Validation of email fixed

# ERROR REPORTING ALL
Set-StrictMode -Version latest

#----------------------------------------------------------
# LOAD ASSEMBLIES AND MODULES
#----------------------------------------------------------
Try
{
  Import-Module ActiveDirectory -ErrorAction Stop
}
Catch
{
  write-log "error" "ActiveDirectory Module couldn't be loaded. Script will stop!"
  Exit 1
}


#----------------------------------------------------------
# LOAD STATIC VARIABLES
#----------------------------------------------------------

function Initialize-StaticVars(){
    new-variable -Scope global -Option ReadOnly, AllScope -name path         -Value $(Split-Path -parent $MyInvocation.MyCommand.Definition)
    new-variable -Scope global -Option ReadOnly, AllScope -name date         -Value $(Get-Date)
    new-variable -Scope global -Option Constant, AllScope -name ADdn         -Value $((Get-ADDomain).DistinguishedName)
    new-variable -Scope global -Option Constant, AllScope -name dnsroot      -Value $((Get-ADDomain).DNSRoot)
    new-variable -Scope global -Option ReadOnly, AllScope -name BackupAD     -Value $(join-path $path "\\backup\\AD_Backup-$(get-date -Format 'yyyy-MM-dd').csv")
    new-variable -Scope global -Option ReadOnly, AllScope -name BackupInput  -Value $(join-path $path "\\backup\\Input_Backup-$(get-date -Format 'yyyy-MM-dd').csv")
    new-variable -Scope global -Option ReadOnly, AllScope -name log          -Value $(join-path $path "\\log\\$(get-date -Format "yyyy-MM-dd").log")
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
    if(test-path -Path .\.env){
        $options = Get-Content -Path .\.env | ConvertFrom-Json
        foreach($opt in $options) {
            new-variable -name $opt.name -value $opt.value -scope $opt.scope -option $opt.option -description $opt.description
        }
    } else {
        write-log "error" ".env not found. Script will stop!"
        Exit 1
    }
}





#----------------------------------------------------------
#START FUNCTIONS
#----------------------------------------------------------

Function invoke-SyncAllUnitedToAD
{
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    write-log "info" "STARTED SCRIPT" -disableWrite:$true
    write-log "warning" "Status of simulation: $Simulation" -disableWrite:$true
    Get-CSVUsers
    Get-ADUsers
        if([math]::Abs($($global:users_CSV).Length-$($global:users_AD).Length)/$($global:users_AD).Length -ge $changeThreshold ) {
            write-log "warning" "Change in users is over $changeThreshold. Due to safety reasons, this script will stop."
        if(!$($interactive)) {exit 1}
    }
    Get-SetResults
    if($interactive) {Read-Host("Continue?")}
    Add-Users
    Set-Users
    Move-Users

    #Clean-Users

}

Function Write-Log{
    Param(
        $loglevel="INFO",
        $data="",
        $disableWrite=$false
    )
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    $oldWIpref = $WhatIfPreference
    $WhatIfPreference = $false
    $timestamp = $(get-date -Format "yyyy-MM-dd HHmmss")
    $full = "$timestamp ["+"$loglevel".ToUpper()+ "]`t`t$data"
    write-host($full)
    if($disableWrite -ne $true){
        $full | Out-File $log -append
        }
    $WhatIfPreference = $oldWIpref
}

Function Get-filteredDataset{
    param(
        [object]$dataset,
        [object]$set=@(),
        [string]$key
    )
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    $set_size = @($set).length
    write-log "info" "There are $dataset_size items that are validated against $set_size"
    # filter dataset with list
    
    
    
    $filteredDataset = @()
    $dataset | ForEach-Object { 
        $data = $_
        $set | ForEach-Object { 
            $item = $_
            if($data.$($key) -eq $item){
                $filteredDataset += $data
                }
            }
        }
    return $filteredDataset
}

Function Get-adfromset{
    param(
        [object]$set=@(),
        [string]$key
    )
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    write-log "info" "There are $(($set).Length) items that are validated against AD"
    $filteredDataset = @()
    $set | ForEach-Object {
        $item = Get-ADUser -LDAPFilter "($($primaryKeyAD)=$_)" -properties 1 2 3  
        $filteredDataset += $item
        }
    return $filteredDataset
}

Function Get-ADUsers
{
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    write-log "info" "There are $(@($users_AD).Length) users in AD"

}

Function Get-CSVUsers
{
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
  $global:csvfile = Get-ChildItem $path/input/*.csv | Sort-Object LastWriteTime | Select-Object -ExpandProperty Name -last 1
  if("$csvfile".Length -eq 0)
  {
    write-log "info" "No CSV-file found. Script will stop!" -disableWrite:$true
    exit 1
    Exit-PSSession
  }
  $global:users_CSV = Import-Csv -Delimiter ';' -encoding default -Path "$path/input/$csvfile" -Verbose 

  write-log "info" "There are $(@($users_CSV).length) users in AllUnited"
}


Function Get-SetResults
{
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>

    $temp_set_AD = $users_AD | foreach-object { $_.$primaryKeyAD } #get column of AD field
    new-variable -name set_AD -Value ($temp_set_AD|Sort-Object -unique) #get only unique values
    write-log "warning" "There are $(@($set_AD).length) users with unique LIDNUMMER in AD"

    $temp_set_CSV = $users_CSV | foreach-object { $_.$primaryKeyCSV } #get column of CSV field
    new-variable -name set_CSV -Value ($temp_set_CSV|Sort-Object -unique) #get only unique values
    write-log "warning" "There are $(@($set_CSV).length) users with unique LIDNUMMER in AllUnited"

        
    $set_edit = Get-SetOperationResult -Left $set_AD -Right $set_CSV -OperationType Intersection
    $set_move = Get-SetOperationResult -Left $set_AD -Right $set_CSV -OperationType Difference-LeftMinusRight
    $set_create = Get-SetOperationResult -Left $set_AD -Right $set_CSV -OperationType Difference-RightMinusLeft
    
    write-log "info" "All users from AD $(@($set_AD).Length) - $(@($set_move).length) Remove + $(@($set_create).length) Create = $(@($set_edit).length) edit. Cross checking every set with AD / CSV:"

    $global:usersEdit = Get-filteredDataset $users_CSV $set_edit $primaryKeyCSV
    $global:usersMove =  Get-filteredDataset $users_AD $set_move $primaryKeyAD
    $global:usersCreate =  Get-filteredDataset $users_CSV $set_create $primaryKeyCSV

    write-log "warning" "There are $(@($global:usersEdit).length) users in AD eligable for edit." 
    write-log "warning" "There are $(@($global:usersMove).length) users to be disabled"
	$list_name=$global:usersMove | select-object -expandproperty displayName | sort-Object  #because list of DN
	$list_name=$list_name -join "`n" | Out-String
	write-log "info" "Disabled users:`n$list_name"
    write-log "warning" "There are $(@($global:usersCreate).length) users to be created from AllUnited"

	$list_name=$global:usersCreate | select-object -expandproperty name2 | sort-Object
	$list_name=$list_name -join "`n" | Out-String

	write-log "info" "To be created users:`n$list_name"
}

Function get-username
{
    param(
        [boolean]$new,
        [string]$firstname,
        [string]$prelastname,
        [string]$lastname
    )
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    $j=0
	$sam_ori=$null
    $p_lastname = $prelastname.ToLower() + $lastname.ToLower()
    $p_lastname = $p_lastname.Replace(",","")
    $p_lastname = $p_lastname.Replace(".","")
    $p_lastname = $p_lastname.Replace(" ","")
    $p_lastname = $p_lastname.Replace("'","")
    $p_lastname = $p_lastname.Replace("-","")
        
    $fullname = $firstname.substring(0,1).ToLower() + $p_lastname

    If($fullname.length -ge 20)
    {
        $fullname = $fullname.substring(0,20)
    }
    $k = $true
    $sam = $fullname

    while($k -eq $true) {
        Try   { $exists = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -Properties useraccountcontrol }
        Catch {  } #if not found,gives error
        If($exists) {
            if ($new){
                write-log "warning" "$sam already exist"
                if (!$sam_ori) {$sam_ori = $sam}
                $j=$j+1
                $sam = $sam_ori+$j
            }
            if (!$new){
                $k = $false
                return($sam)
            }
        }
        If(!$exists) {
            write-log "info" "$sam is new username"
            $k=$false
            return($sam)
            }
    }
}

function Optimize-phonenumber($no)
{
    <#
    .DESCRIPTION
    #Count Name                      Group
#Count Name                      Group                                                                                                                              
    #Count Name                      Group
    #----- ----                      -----
#----- ----                      -----                                                                                                                              
    #----- ----                      -----
    #  895 10                        {0612345678...}
#  895 10                        {0612345678...}                                                                                
    #  895 10                        {0612345678...}
    #    2 13                        {0035712345678, 0013012345678}
    #    4 14                        {00441234567891}
    #    3 9                         {061234567 }
#    3 9                         {061234567 }                                                                                                  
    #    3 9                         {061234567 }
    #    2 11                        {03212345679}
    #    4 12                        {031612345678, 040123456789, 031687654321}
    #    1 15                        {004912345678901}
    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>

    $type=$null
    $result = @()
    $var=[string]$no
    $var= $var.trim() #remove spaces
    $len = $var.Length
    #number can be between 8-15 digits. https://en.wikipedia.org/wiki/E.164
    If ($len -eq 10) #10=perfect 0612345678 071 1234567
    {
        $type=$null
        $res=$var -replace '^0', '+31'
    }
     
    Else #wtf
    {
        $res=$var
        $type="No_Change_$len"
    
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
            Type = $type;
            }
    return $result


}

function Remove-StringLatinCharacters
{
    PARAM (
        [string]$String
    )
    <#
    .DESCRIPTION

    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>
    [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
}

Function Add-Users
{
    <#
  <# 
    <#
    .DESCRIPTION
     Create user in AD based on global:usersCreate
    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>

    $i=0
    $global:usersCreate | ForEach-Object {

    $EmployeeID = $_.contactid
    $DisplayName = Remove-StringLatinCharacters($_.name2)
    $lastname = Remove-StringLatinCharacters($_.lastname)
    $initials = Remove-StringLatinCharacters((($_.initials).replace(".","")).replace(" ",""))
    $pre = Remove-StringLatinCharacters($_.prelastname)
    $GivenName = Remove-StringLatinCharacters($_.firstname)
    $Phone = $($_.phone2).replace("-","")
	$Phone = optimize-phonenumber($Phone)
    $EmailAddress = $($_.email).trim()
    $Description = $_.value08
    $Employeenumber = $_.value08

    $password = ([char[]]([char]32..[char]122) | sort-Object {Get-Random})[0..50] -join ''

     #(([char[]]([char]65..[char]90)+[char[]]([char]97..[char]121)+[char[]]([char]48..[char]57) | sort {Get-Random})[0..50] -join ''



      If (($displayName -eq "") -Or ($GivenName -eq "") -Or ($LastName -eq ""))
      {
        write-log "error" "Please provide valid Full Name, GivenName and LastName. Processing skipped for user $($i): $($displayName), $($Description)."
      }
      Else # Valid Full, given, lastname
      {

        $location = $TargetOU + ",$($addn)"  # Set the target OU
        $sam = get-username $true $givenname $pre $lastname
        Try   {
          $exists = Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" # get any user with saameacocuntanem,
          $exists = Get-ADUser -LDAPFilter "(Description= $Description)" #get any user with specific description, possibly not needed after checking SetFunctions
          $exists = Get-ADUser -LDAPFilter "(employeeID=$employeeID)" #get anny user with specific employeeID, possibly not needed after checking SetFunctions
        } #does samaccountname exist?
        Catch { }
        If(!$exists) #does not exist
        {
          # Set all variables according to the table names in the Excel
          # sheet / import CSV. The names can differ in every project, but
          # if the names change, make sure to change it below as well.
          $setpass = ConvertTo-SecureString -AsPlainText $password -force

          Try
          {
            write-log "info" "Creating user : $($sam)"
            $WhatIfPreference = $simulation
            New-ADUser $sam -DisplayName $DisplayName `
             -GivenName $GivenName -Initials $initials -Surname $pre$lastname `
             -Description $Description -EmailAddress $EmailAddress -OfficePhone $phone `
             -UserPrincipalName ($sam + "@" + $dnsroot) `
             -EmployeeID $EmployeeID `
             -EmployeeNumber $Employeenumber `
             -AccountPassword $setpass `
            -profilePath "$ProfilePath$sam" -homeDirectory "$HomeDirectory$sam" `
            -homeDrive $homeDrive -Enabled $enabled `
			-OtherAttributes @{mailnickname=$sam}
            $WhatIfPreference = $false

            write-log "info" "Created new user : $($sam)"

            $dn = (Get-ADUser $sam).DistinguishedName

            # Move the user to the OU ($location) you set above. If you don't
            # want to move the user(s) and just create them in the global Users
            # OU, comment the string below
            If ([adsi]::Exists("LDAP://$($location)"))
            {
              $WhatIfPreference = $simulation
              Move-ADObject -Identity $dn -TargetPath $location
              $WhatIfPreference = $false
              write-log "info" "User $sam moved to target OU : $($location)"

            }
            Else
            {
              write-log "error" "Targeted OU couldn't be found. Newly created user wasn't moved!"

            }

            # Rename the object to a good looking name (otherwise you see
            # the 'ugly' shortened sAMAccountNames as a name in AD. This
            # can't be set right away (as sAMAccountName) due to the 20
            # character restriction
            $newdn = (Get-ADUser $sam).DistinguishedName

            Add-ADGroupMember -Identity $TargetGroup -Members $newdn
            write-log "info" "$sam was added to Target Group"

            $WhatIfPreference = $simulation
            Rename-ADObject -Identity $newdn -NewName $DisplayName
            $WhatIfPreference = $false
            write-log "info" "Renamed $($sam) to $displayName."



          }
          Catch
          {
            write-log "error" "Oops, something went wrong: $($_.Exception.Message)"
          }
        }
        Else
        {
          write-log "error" "User $($sam) ($($GivenName) $($LastName)) already exists or returned an error!"

        }
      }
    $i++
  }
  write-log "info" "$i users were created."
}

Function Set-Users #account both in AU and AD
{
    <#
    .DESCRIPTION
     Create user in AD based on global:usersCreate
    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>    
    $i=1
    $global:usersEdit | ForEach-Object {
        $EmployeeID = $_.contactid
        $DisplayName = Remove-StringLatinCharacters($_.name2)
        $Surname = Remove-StringLatinCharacters($_.lastname)
        $Initials = Remove-StringLatinCharacters((($_.initials).replace(".","")).replace(" ",""))
        $pre = Remove-StringLatinCharacters($_.prelastname)
        $GivenName = Remove-StringLatinCharacters($_.firstname)
        $OfficePhone = $($_.phone2).replace("-","")
        $EmailAddress = ($_.email).trim()
        $Description = $_.value08
        $EmployeeNumber = $_.value08
        

        $userAD=Get-ADUser -LDAPFilter "($($primaryKeyAD)=$($_.$primarykeyCSV))" -Properties `
            DistinguishedName, DisplayName, EmployeeID, Description, EmailAddress, OfficePhone,  Initials, GivenName, Surname, Employeenumber
        
		$EmailAddress_old = $userAD.EmailAddress
		$OfficePhone_old = $userAD.OfficePhone 
		$EmployeeNumber_old = $userAD.EmployeeNumber 
		$EmployeeID_old = $userAD.EmployeeID 
		$Initials_old = $userAD.Initials 
		$GivenName_old = $userAD.GivenName 
		$Surname_old = $userAD.Surname 
		$Description_old = $userAD.Description 
        $DisplayName_old = $userAD.DisplayName

		
        #security (2 out of 3 vars need to stay static)
        $test_disp = $userAD.Displayname -eq $displayName #equal displayname
        $test_eid = $userAD.EmployeeID -eq $EmployeeID #equal employeeid
        $test_desc = $userAD.Description -eq $description #equal description
        $test23 = $test_disp -and ($test_eid -or $test_desc) -or ($test_eid -and $test_desc); #2 out of 3 need to be true
        
        $update = ""
        if($test23) {
          if(($userAD.EmailAddress -ne $EmailAddress) -and ($EmailAddress.length -gt 0)){ $userAD.EmailAddress = $EmailAddress; $update+="email[$EmailAddress_old => $EmailAddress]," }
          if(($userAD.OfficePhone -ne $OfficePhone) -and ($OfficePhone.length -gt 0)){ $userAD.OfficePhone = $OfficePhone; $update+="Phone[$OfficePhone_old => $OfficePhone]," }
          if(($userAD.EmployeeNumber -ne $EmployeeNumber) -and ($EmployeeNumber.length -gt 0)){ $userAD.Employeenumber = $EmployeeNumber; $update+="EmployeeNumber[$EmployeeNumber_old => $EmployeeNumber]," }
          if(($userAD.EmployeeID -ne $EmployeeID) -and ($EmployeeID.length -gt 0)){ $userAD.EmployeeID = $EmployeeID; $update+="EmployeeID[$EmployeeID_old => $EmployeeID]," }
          if(($userAD.Initials -ne $Initials) -and ($Initials.length -gt 0)){ $userAD.Initials = $Initials; $update+="Initials[$Initials_old => $Initials]," }
          if(($userAD.GivenName -ne $GivenName) -and ($GivenName.length -gt 0)){ $userAD.GivenName = $GivenName;$update+="GivenName[$GivenName_old => $GivenName]," }
          if(($userAD.Surname -ne $("$pre $Surname").trim()) -and ($("$pre $Surname").trim().length -gt 0)){ $userAD.Surname = $("$pre $Surname").trim(); $update+="Surname[$Surname_old => $Surname]," }
          if(($userAD.Description -ne $Description) -and ($Description.length -gt 0)){ $userAD.Description = $Description; $update+="Description[$Description_old => $Description]," }
          if(($userAD.DisplayName -ne $DisplayName) -and ($DisplayName.length -gt 0)){ $userAD.DisplayName = $DisplayName; $update+="DisplayName[$DisplayName_old => $DisplayName]," }
        }
        else {
          write-log "info" "$DisplayName_old unable to update due too much desc/displayname/employeeid change"
        }
        
        if($update.Length -gt 0){
            $WhatIfPreference = $simulation
            Set-ADUser -Instance $userAD
            $WhatIfPreference = $false
            write-log "info" "$DisplayName_old is updated with $update"
            $i++
        }
        
    }
    write-log "info" "$i users were updated with new data."  

}

Function Move-Users
{
    <#
  <# 
    <#
    .DESCRIPTION
    Movement of user & data
    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #>    
  #>
    #>    

    $i=1
    $global:usersMove | ForEach-Object {
        $samaccountname=$_.sAMAccountName #WIP
        $user=$_.DistinguishedName
        if($($_.displayName) -ne "_IGNORE_USERS") {
        
        $password = ([char[]]([char]32..[char]122) | Sort-Object {Get-Random})[0..50] -join ''
        $setpass = ConvertTo-SecureString -AsPlainText $password -force
        $description = "Disabled_$(get-date -Format "yyyy-MM-dd")__$($_.description)"
        $WhatIfPreference = $simulation
<# 
        $targetHD="$homedirecory_direct\_old\$samaccountname"
        $targetPP="$profilepath_direct\_old\$samaccountname.?"
        
        
        Move-Item -Path "$homeDirectory_direct\$samaccountname" -Destination "$targetHD" -Force
        Move-Item -Path "$profilepath_direct\$samaccountname.?" -Destination "$targetPP" -Force #>

        #Set-ADUser -Identity $user -clear mail,telephoneNumber  -Enabled $False -Description $description -HomeDirectory "$homedirectory/_old/$samaccountname" -ProfilePath "$profilepath/_old/$samaccountname"        
		Set-ADUser -Identity $user -clear mail,telephoneNumber  -Enabled $False -Description $description #remove mail / phone and disable user
        Set-ADAccountPassword -Identity $user -NewPassword $setpass -Reset
        Remove-ADGroupMember -Identity $TargetGroup -Members $user -confirm:$false 
        Move-ADObject -Identity $user -TargetPath $disabledOU
        write-log "info" "$($_.name) is cleared and password randomized."  
        $WhatIfPreference = $false
        $i++
        }
     }
     write-log "info" "$i users have been disabled and moved."
}

function Clear-users {
    <#
    .DESCRIPTION
    Movement of user & data
    .PARAMETER Extension
    Specifies the extension. "Txt" is the default.

    .INPUTS
    None.

    .OUTPUTS
    System.String. Add-Extension returns a string with the extension or file name.

    .EXAMPLE
    PS> extension -name "File"
    File.txt
    #> 

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
function invoke-PostCleanUp(){
    $WhatIfPreference = $simulation
    $DatetoDelete = $Date.AddDays($LogRetentionDays)
    Get-ChildItem $path/input/*.log| Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item #delete logs older than 30 days
    Copy-Item "$path/input/$global:csvfile" -Destination $backupinput
    remove-item "$path/input/$global:csvfile"
    write-log "info" "Removed CSV file"
    $WhatIfPreference = $false
    write-log "info" "STOPPED SCRIPT"
    Copy-Item "$log" -Destination "$path/input"
    Exit-PSSession
}

Initialize-StaticVars
Import-Config #import config
. "$path\\SetOperations.ps1" #dot source set-operations
Invoke-SyncAllUnitedToAD #the whole program
Invoke-PostCleanUp #cleanup and move files