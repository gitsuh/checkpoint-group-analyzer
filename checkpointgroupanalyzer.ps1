$starttime = get-date
$logdatefile = ".$(Get-Date -format "yyyy-MM-dd_hh_ss").csv"
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$checkpointcredsfile = ".\checkpointcredsfile.xml"
$grouplistcsvfile = ".\checkpointgroups.csv"
$checkpointgroupconfig = ".\checkpointgroupsconfig.json"
#need to implement config check to validate json config rather than just check for file
if($(test-path $checkpointgroupconfig) -eq $false)
{
	$configjsonbaseurl = read-host -prompt "Enter Checkpoint base URL. (e.g. 'https://192.168.100.2')"
	$configjsonbasereportname = read-host -prompt "Enter base report name. (e.g. '.\myreport' will output '.\myreport.yyyy-MM-dd_hh_ss.csv')"
@{
"baseurl" = $configjsonbaseurl
"basereportname" = $configjsonbasereportname
} | convertto-json | out-file $checkpointgroupconfig
}
if($(test-path $checkpointcredsfile) -eq $false)
{
	$checkpointcreds = get-credential -Message "Enter login credentials"
	$checkpointcreds | export-clixml $checkpointcredsfile -Force
}
if($(test-path $grouplistcsvfile) -eq $false)
{
		throw "No grouplist.csv"
}
$baseurl = (get-content $checkpointgroupconfig | convertfrom-json).baseurl
$basereport = (get-content $checkpointgroupconfig | convertfrom-json).basereportname
if($(test-path $("$basereport.$logdatefile")) -eq $true)
{
		throw "Report name already exists. $basereport.$logdatefile"
}
if($(test-path $("$basereport.exception.$logdatefile")) -eq $true)
{
		throw "Report name already exists. $basereport.$logdatefile"
}
$checkpointcreds = import-clixml $checkpointcredsfile
$checkpointuser = $checkpointcreds.UserName
$checkpointpass = $checkpointcreds.GetNetworkCredential().Password
$loginheader = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$loginheader.Add('Content-Type','application/json')
$loginuri = $baseurl + "/web_api/login"
$logincontenttype = "application/json"
$loginmethod = "POST"
$loginbody = @{
"user" = $checkpointuser
 "password" = $checkpointpass
} | convertto-json
$loginjson = Invoke-RestMethod -Method $loginmethod -Uri $loginuri -TimeoutSec 100 -Body $loginbody -headers $loginheader -ContentType $logincontenttype
$sid = $loginjson.sid
$checkpointauthheader = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$checkpointauthheader.Add('X-chkp-sid',$sid)
$grouplist = import-csv -path $grouplistcsvfile
$grouplistgood = @()
$whereusedcontenttype = "application/json"
$whereuseduri = $baseurl + "/web_api/where-used"
$whereusedmethod = "POST"		
$report = @()
$reportexception = @()
foreach($item in $grouplist){
	$whereusedbody = @{"name" = $($item.groupname)} | convertto-json
	$resultjson = $null
	try{
		$resultjson = Invoke-RestMethod -Method $whereusedmethod -Uri $whereuseduri -TimeoutSec 100 -Body $whereusedbody -headers $checkpointauthheader -ContentType $whereusedcontenttype
	}catch{
		write-host "Could not find $($item.groupname)"
		$reportexception += $item.groupname
	}
	$parentgroupname = $resultjson.'used-directly'.objects.name
	$parentgroupuid = $resultjson.'used-directly'.objects.uid
	$parentgrouptype = $resultjson.'used-directly'.objects.type
	$tempobj = New-Object System.Object
	$tempobj | add-member -name "groupname" -membertype NoteProperty -value $item.groupname
	$tempobj | add-member -name "parentgroupname" -membertype NoteProperty -value $parentgroupname
	$tempobj | add-member -name "parentgroupuid" -membertype NoteProperty -value $parentgroupuid
	$tempobj | add-member -name "parentgrouptype" -membertype NoteProperty -value $parentgrouptype
	$report += $tempobj
}
$report | out-gridview
$reportexception | out-gridview

$report | export-csv -notypeinformation "$basereport.$logdatefile"
$reportexception | export-csv -notypeinformation "$basereport.exception.$logdatefile"

write-host "Logging out..."
$logouturi = $baseurl + "/web_api/logout"
$logoutcontenttype = "application/json"
$logoutresultjson = Invoke-RestMethod -Method "POST" -Uri $logouturi -TimeoutSec 100 -headers $checkpointauthheader -ContentType $logoutcontenttype

write-host $logoutresultjson
