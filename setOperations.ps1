<#
.SYNOPSIS
    Performs "set" operations
 
.DESCRIPTION
     
    Given two sets, does Union, Intersection, Difference and Complement
 
.INPUTS
    Two sets
 
.OUTPUTS
    The results of the set operation
         
.EXAMPLE
 
    $a = (1,2,3,4)
    $b = (1,3,4,5)
 
    Get-SetOperationResult -Left $a -Right $b -OperationType Union
    1
    3
    4
    5
    2
 
    Get-SetOperationResult -Left $a -Right $b -OperationType Intersection
    1
    3
    4
 
    Get-SetOperationResult -Left $a -Right $b -OperationType Difference-LeftMinusRight
    2
 
    Get-SetOperationResult -Left $a -Right $b -OperationType Difference-RightMinusLeft
    5
 
    Get-SetOperationResult -Left $a -Right $b -OperationType ComplementLeft
    5
 
    Get-SetOperationResult -Left $a -Right $b -OperationType ComplementRight
    2
 
.EXAMPLE
 
    #Find the properties in first object that are not in second!
    #  Notice that the Create/Update columns do not exist in the second object
 
    $databaseTypeObject1 = New-Object System.Object
    $databaseTypeObject1 | Add-Member -type NoteProperty -name DatabaseType -value 'Oracle'
    $databaseTypeObject1 | Add-Member -type NoteProperty -name Vendor       -value 'Oracle Corporation'
    $databaseTypeObject1 | Add-Member -type NoteProperty -name DatabaseName -value 'Oracle'
    $databaseTypeObject1 | Add-Member -type NoteProperty -name Description  -value 'Oracle database'
    $databaseTypeObject1 | Add-Member -type NoteProperty -name CreateUser   -value $env:USERNAME
    $databaseTypeObject1 | Add-Member -type NoteProperty -name CreateDate   -value (Get-Date)
    $databaseTypeObject1 | Add-Member -type NoteProperty -name UpdateUser   -value $env:USERNAME
    $databaseTypeObject1 | Add-Member -type NoteProperty -name UpdateDate   -value (Get-Date)
 
    $databaseTypeObject2 = New-Object System.Object
    $databaseTypeObject2 | Add-Member -type NoteProperty -name DatabaseType -value 'Sybase'
    $databaseTypeObject2 | Add-Member -type NoteProperty -name Vendor       -value 'SAP1'
    $databaseTypeObject2 | Add-Member -type NoteProperty -name DatabaseName -value 'Sybase'
    $databaseTypeObject2 | Add-Member -type NoteProperty -name Description  -value 'Sybase'
 
     
    Get-SetOperationResult `
        -Left ($databaseTypeObject1 | Get-Member -MemberType Properties | Select-Object -Expand Name) `
        -Right ($databaseTypeObject2 | Get-Member -MemberType Properties | Select-Object -Expand Name) `
        -OperationType Difference-LeftMinusRight
 
.NOTES
    Pretty self-explanatory. See "Set Theory" for a refresher link below if needed.
 
Version History
    Created by Jana Sattainathan | Twitter @SQLJana | WordPress: SQLJana.WordPress.com
    - Used idea from referenced URL and built this function
 
.LINK
    http://stackoverflow.com/questions/8609204/union-and-intersection-in-powershell
    http://www.cs.odu.edu/~toida/nerzic/content/set/set_operations.html
#>
 
 
function Get-SetOperationResult
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true,
                   Position=0)]
        [object[]]
        $Left,
 
        [Parameter(Mandatory=$true,
                   Position=1)]
        [object[]]
        $Right,
 
        [Parameter(Mandatory=$false,
                   Position=2)]
        [ValidateSet("Union","Intersection","Difference-LeftMinusRight","Difference-RightMinusLeft","ComplementLeft","ComplementRight")]
        [string]
        $OperationType="Intersection"
    )
     
     
    BEGIN
    {       
    }
     
    PROCESS
    {
         
        [object] $result = @()
 
        #-----------
        #Union = Given two sets, the distinct set of values from both
        #-----------
        if ($OperationType -eq 'Union')
        {
            $result = Compare-Object $Left $Right -PassThru -IncludeEqual                   # union
        }
 
        #-----------
        #Intersection = Given two sets, the distinct set of values that are only in both
        #-----------
        if ($OperationType -eq 'Intersection')
        {
            $result = Compare-Object $Left $Right -PassThru -IncludeEqual -ExcludeDifferent # intersection
        }
 
        #-----------
        #Difference = Given two sets, the values in one (minus) the values in the other
        #-----------
        if ($OperationType -eq 'Difference-LeftMinusRight')
        {
            $result = $Left | Where-Object {-not ($Right -contains $_)}
        }
        if ($OperationType -eq 'Difference-RightMinusLeft')
        {
            $result = $Right | Where-Object {-not ($Left -contains $_)}
        }
         
        #-----------
        #Complement = Given two sets, everything in the universe which is the UNION (minus) the values in the set being "Complemented"
        #-----------
        if ($OperationType -eq 'ComplementLeft')
        {
            $result = Compare-Object $Left $Right -PassThru -IncludeEqual |                  # union
                                Where-Object {-not ($Left -contains $_)}
        }
        if ($OperationType -eq 'ComplementRight')
        {
            $result = Compare-Object $Left $Right -PassThru -IncludeEqual |                  # union
                                Where-Object {-not ($Right -contains $_)}
        }
         
        Write-Output $result
    }
     
    END
    {
    }
}
