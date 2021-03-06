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
#STATIC VARIABLES
#----------------------------------------------------------
$path     = Split-Path -parent $MyInvocation.MyCommand.Definition
#$newpath  = $path + "\import_create_ad_users.csv" #WIP
$backup      = $path + "\backup\AD_Backup-$(get-date -Format "yyyy-MM-dd").csv"
$log      = $path + "\log\$(get-date -Format "yyyy-MM-dd").log"
$log_del_day = "-30"
$date     = Get-Date
$ADdn     = (Get-ADDomain).DistinguishedName
$dnsroot  = (Get-ADDomain).DNSRoot

$TargetOU = "OU=A,OU=B,OU=C"
$disabledOU="OU=A,OU=B,OU=C,$addn"
$contactOU = "OU=A,OU=B,OU=C,$addn"
$TargetGroup ="CN=D,OU=A,OU=B,OU=C,$addn" 
#$expires  = $True #WIP
$enabled  = $True

#sync keys of csv and AD
$primaryKeyCSV = "contactid" #### WARNING!!!! contactid<=>employeeID // value08<=>description/employeeNumber
$primaryKeyAD = "employeeID" #### WARNING !!
$changeThreshold = 0.25

$homeDrive = "H"
$homeDirectory = "\\$dnsroot\DFS\Homes\"
$profilePath =  "\\$dnsroot\DFS\Profiles\"
#$homeDirectory_direct = "F:\Homes" #WIP
#$profilePath_direct = "F:\Profiles" #WIP

$i        = 1
#----------------------------------------------------------
# LOAD Source Dot Scripts
#----------------------------------------------------------

. "$path\SetOperations.ps1"


#----------------------------------------------------------
#START FUNCTIONS
#----------------------------------------------------------
Function Start-Commands
{
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
  #Move-Users
  
  #Clean-Users #WIP
  
}

Function write-log{
    Param(
        $loglevel="INFO",
        $data="",
        $disableWrite=$false
    )
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
    param([object]$dataset, [object]$set=@(), [string]$key)
    $dataset_size = @($dataset).length
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
    param([object]$set=@(), [string]$key)
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

    $global:users_AD = Get-ADUser -filter * -Properties displayName,sn,initials,givenName,mail,telephoneNumber,description,sAMAccountName,EmployeeID,Employeenumber -ResultSetSize $null -SearchBase $targetOU
    $global:users_AD | export-csv -Path $backup -Delimiter ";" 
    write-log "info" "Created backup of all Users"
    write-log "info" "There are $(@($users_AD).Length) users in AD"
	write-log "info" "Status phonenumbers: `n$($global:users_AD | Select-Object -ExpandProperty officephone | group-object length | format-table)"
    
}

Function Get-CSVUsers
{
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
    param([boolean]$new,[string]$firstname,[string]$prelastname,[string]$lastname )
    
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

function optimize-phonenumber($no) 
{

#Count Name                      Group                                                                                                                              
#----- ----                      -----                                                                                                                              
#  895 10                        {0612345678...}                                                                                
#    2 13                        {0031712345678, 0011012345678}                                                                                                     
#    4 14                        {00111234567891}                                                                   
#    3 9                         {061234567 }                                                                                                  
#    2 11                        {09212345679}                                                                                                         
#    4 12                        {031612345678, 080123456789, 031687654321}                                                                           
#    1 15                        {009912345678901}                            

    
	
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
    PARAM ([string]$String)
    [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String))
}

Function Add-Users
{
  <# 
  Create user in AD based on global:usersCreate

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
            write-log "info" "$sam was added to target group"

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
  Movement of user & data
  
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

function Clear-users{
    #WIP

    $userBase=Search-ADAccount -UsersOnly -SearchBase $disabledOU -AccountInactive -TimeSpan 365 | where-object{$_.enabled -eq $false} | Get-ADUser -Properties Name, sAMAccountName, description,employeeID,employeeNumber whenChanged,whenCreated  | Select-object Name, sAMAccountName, description,employeeID,Employeenumber, whenChanged,whenCreated 
    New-ADObject -name "$($_.Name) [$($_.description)]" -type contact -Description $_.description -OtherAttributes @{'employeeID'="$_.employeeID"; 'info'="Relatienummer: $_.employeeID`nEmployeeNumber: $_.employeenumber`nWhenCreated: $_.whenCreated`nWhenChanged: $_.whenChanged"} -path $contactOU

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


Start-Commands #whole program
$WhatIfPreference = $simulation

$DatetoDelete = $Date.AddDays($log_del_day)
Get-ChildItem $path/input/*.log| Where-Object { $_.LastWriteTime -lt $DatetoDelete } | Remove-Item #delete logs older than 30 days
remove-item "$path/input/$global:csvfile"
write-log "info" "Removed CSV file"
$WhatIfPreference = $false
write-log "info" "STOPPED SCRIPT"
Copy-Item "$log" -Destination "$path/input"
Exit-PSSession

