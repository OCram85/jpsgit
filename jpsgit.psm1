#requires -version 5.0

class Event {
    [PSObject]$actor
    [PSObject]$Assignee
    [PSObject]$Assigner
    [PSObject]$commit_id
    [URI]$commit_url
    [DateTime]$created_at
    [string]$event
    [int]$id
    [PSObject]$label
    [PSObject]$rename
    [URI]$url
}
Update-TypeData -TypeName Event -DefaultDisplayPropertySet Created_at,Event,Login   -DefaultKeyPropertySet id -Force
Update-TypeData -TypeName Event -MemberType ScriptProperty -MemberName Login -Value {$this.Actor.login} -force

class Issue {
    [PSObject]$Assignee
    [PSObject[]]$Assignees
    [string]$Body
    [string]$Closed_at
    [PSObject]$closed_by
    [int]$comments
    [URI]$comments_url
    [Datetime]$created_at
    [URI]$events_url
    [URI]$html_url
    [int]$id
    [PSObject[]]$labels
    [URI]$labels_url
    [bool]$locked
    [PSObject]$milestone
    [int]$number
    [PSObject]$pull_request
    [URI]$repository_url
    [string]$State
    [string]$Title
    [Datetime]$Updated_at
    [string]$Url
    [PSObject]$User
}

class PipeableIssue : Issue {
    [String]$RepoOwner
    [String]$Repository
    [Int]$issue
    [Timespan]Get_Freshness() {
        return [DateTIme]::Now - $this.updated_at
    }
    [Event[]]GetEvents() {
        $list = @()
        $items = Invoke-RestMethod -Uri $this.events_url 
        foreach ($c in $items) {
            $list += [Event]$c
        }
        return $list
    }
}

Update-TypeData -TypeName Issue -DefaultDisplayPropertySet Number,State,Login,Comments,Title -DefaultDisplayProperty title  -DefaultKeyPropertySet id -Force
Update-TypeData -TypeName Issue -MemberType ScriptProperty -MemberName Login -Value {$this.User.login} -force


class Comment {
    [string]$body
    [DateTime]$created_at
    [URI]$html_url
    [int]$id
    [URI]$issue_url
    [string]$updated_at
    [string]$url
    [PSObject]$user

}
Update-TypeData -TypeName Comment -DefaultDisplayPropertySet id,body -DefaultDisplayProperty Title  -DefaultKeyPropertySet id -Force
Update-TypeData -TypeName Comment -MemberType ScriptProperty -MemberName Login -Value {$this.User.login} -force


function Get-GitIssue {
    [CmdletBinding(DefaultParameterSetName="Query")]
    [OutputType([PipeableIssue], ParameterSetName="Query")]
    [OutputType([PipeableIssue], ParameterSetName="Issue")]
    [OutputType([Comment],       ParameterSetName="Comments")]
    [OutputType([Event],         ParameterSetName="Events")]
    Param (
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [String]
        [Alias("Owner")]
        $RepoOwner = "PowerShell",

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [String]
        [Alias("Repo")]
        $Repository = "PowerShell-RFC",

        [Parameter()]
        [ValidateRange(1,100)]
        [parameter(ParameterSetName="Query")]
        [Parameter(ParameterSetName="Comments")]
        [Int]
        $PerPage=100,

        [Parameter()]
        [parameter(ParameterSetName="Query")]
        [Parameter(ParameterSetName="Comments")]
        [ValidateRange(1,[int]::MaxValue)]
        [Int]
        $Page=0,

        [Parameter()]
        [PSCredential]
        [System.Management.Automation.CredentialAttribute()]
        $Credential, 

        [parameter(ParameterSetName="Query")]
        [ValidateSet("open","closed","all")]
        [string]$State="all",

        [parameter(ParameterSetName="Query")]
        [string]$Mentioned = $Null,

        [parameter(ParameterSetName="Query")]
        [string[]]$Label = $Null,

        [parameter(ParameterSetName="Query")]
        [Datetime]$Since = 0,

        [Parameter(ParameterSetName="Issue"   , Position=0, mandatory=1, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName="Comments", Position=0, mandatory=1, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName="Events"  , Position=0, mandatory=1, ValueFromPipelineByPropertyName=$true)]
        [int]
        $Issue = [Int]::maxValue,

        [Parameter(ParameterSetName="Comments", mandatory=1)]
        [Switch]
        $Comments, 

        [Parameter(ParameterSetName="Events",  mandatory=1)]
        [Switch]
        $Events
    )

    begin {
        $State = $State.ToLower()
        $MoreParams = @{}
        if ($Credential) {
            $pair = "$($cred.UserName):$($cred.GetNetworkCredential().password)"
            $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

            $basicAuthValue = "Basic $encodedCreds"

            $Headers = @{
                Authorization = $basicAuthValue
            }

            $MoreParams = @{Headers=$Headers}
        }
    }
    process {
        Switch ($PSCmdlet.ParameterSetName) {
            "Issue" {
                $uri = "https://api.github.com/repos/$RepoOwner/$Repository/issues/$issue"
                Write-Verbose "URI $uri"
                $IssueSet = Invoke-RestMethod -Uri $URI @MoreParams
                foreach ($i in $IssueSet) {
                    $p = [PipeableIssue]$i
                    $p.RepoOwner   = $owner
                    $p.Repository  = $repo
                    $p.Issue = $p.number
                    Write-Output $p
                }
            }
            "Query" {
                $uri = "https://api.github.com/repos/$RepoOwner/$Repository/issues?state=$State&per_page=$PerPage"
                if ($Mentioned) {
                    $uri += "&mentioned=$Mentioned"
                }
                if ($Label) {
                    $uri += "&labels=$($Label -join ",")"
                }
                if ($Since -ne [Datetime]0) {
                    $uri += "&since=$(([dateTime]$Since).ToString("yyyy-MM-ddTHH:mm:ss"))"
                }

                if ($Page -ne 0) {
                    #The specified a page
                    $CurrentPage = $Page
                }
                else {
                    $CurrentPage = 1
                }
                for (; ;) {
                    $uri += "&page=$CurrentPage"
                    Write-Verbose "URI $uri"
                    $issueSet =  Invoke-RestMethod -Uri $uri @MoreParams
                    if (!($issueset)) {break}
                    Write-Verbose ("Page {0} ISSUE SET has {1} items" -f $CurrentPage,$issueSet.count)
                    foreach ($i in $issueSet) {
                        $p = [PipeableIssue]$i
                        $p.RepoOwner   = $owner
                        $p.Repository  = $repo
                        $p.Issue = $p.number
                        Write-Output $p
                    }
                    if ($Page -ne 0) {break}
                    $CurrentPage++
                }

            }
            "Comments" {
                $uri = "https://api.github.com/repos/$RepoOwner/$Repository/issues/$issue/comments?page=$Page&per_page=$PerPage"
                Write-Verbose "URI $uri"
                $items = Invoke-RestMethod -Uri $URI @MoreParams
                foreach ($c in $items) {
                    [Comment]$c
                }
            }
            "Events" {
                $uri = "https://api.github.com/repos/$RepoOwner/$Repository/issues/$issue"
                Write-Verbose "URI $uri"
                $IssueSet = Invoke-RestMethod -Uri $URI @MoreParams
                foreach ($i in $IssueSet) {
                    if ($i.events_url) {
                        $list = @()
                        Write-Verbose "Events URL: $($i.events_url)"
                        $EventSet = Invoke-RestMethod -Uri ($i.events_url) @MoreParams
                        foreach ($e in $EventSet) {
                            write-output ([Event]$e)
                        }
                    }
                }
            }
        }
    }
}
Set-Alias ggi Get-GitIssue

#region Helper Function
function Convert-ObjecttoClass {
    [CmdletBinding()]
    [OutputType([String])]
    Param (
        # Param1 help description
        [Parameter(Mandatory=1)]
        $InputObject,

        [Parameter(Mandatory=1)]
        [String]$ClassName
    )

    @" 
class $ClassName { 
$(foreach ($p in Get-Member -InputObject $InputObject -MemberType Properties |Sort-Object name)
{ 
    switch ($p.MemberType) { 
        "NoteProperty" { 
            $type = ($p.Definition -split " ")[0] 
            if ($type -eq "System.Management.Automation.PSCustomObject") {
                "`t[PSObject]`$$($p.Name);`n" 
            }
            else {
                "`t[$type]`$$($p.Name);`n" 
            }
        }
    }
}
)
}
"@
}

#endregion