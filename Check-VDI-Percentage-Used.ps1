
# Author: Megan Fuhr
# Date: 2020.01.09
# Description: This script will review all single user OS delivery groups that do not have the word TEST in the name, pull the desktops that are not in maintenance mode
#               and see if the capacity used is greater than 85%.  If so, an email wll be sent.  Subsequent runs will update the recipients only if a delivery group has
#               recovered or a new delivery group is experiencing usage of over 95%.  It leverages a .csv to keep track of previous runs.

#requires -Version 5

begin {
    try {
        Add-PSSnapin Citrix.* -ErrorAction SilentlyContinue
    }
    Catch {RETURN}
    
    $DDCs = Get-Content -Path "PathToCSVContainingDDCs.csv"
    $badFilePath = "PathToSaveOutput.csv"
    $temp = @()
    $recovered = @()
    $Output = @()
    $previousBadList = @()
    $newBadList = @()
    $stillbadlist = @()
    $allBad = @()

    if (-not(Test-Path -Path $badFilePath)) {        
        Out-File -FilePath $badFilePath
    }
    else {
        $previousbadlist = Import-CSV -Path $badFilePath
    }

    $css = @"
<html>
<head>
<style>
#citrix {
    font-family: "Trebuchet MS", Arial, Helvetica, sans-serif;
    border-collapse: collapse;
    width: 100%;
  }
  
  #citrix td, th {
    border: 1px solid #ddd;
    padding: 8px;
  }
  
  #citrix tr:nth-child(even){background-color: #f2f2f2;}
  
  #citrix tr:hover {background-color: #ddd;}
  
  #citrix th {    
    padding-top: 12px;
    padding-bottom: 12px;
    text-align: left;
    background-color: #9F1818;
    color: white;
  }

  h2 {
    font-family: "Trebuchet MS", Arial, Helvetica, sans-serif;
    }

  </style>
  </head>
  <body>
"@
}

Process {
    Foreach ($ddc in $ddcs) {
        $deliverygroups = Get-BrokerDesktopGroup -AdminAddress $ddc -MaxRecordCount 10000 | `
                where {(((($_.SessionSupport -eq "SingleSession") `
                    -and ($_.IsRemotePC -eq $false)) `
                    -and ($_.Name -notlike "*test*") `
                    -and ($_.DesktopKind -eq "Shared") `
                ))}
        foreach ($group in $deliverygroups) {
            $desktopsTotal = Get-BrokerDesktop -AdminAddress $ddc -MaxRecordCount 10000 -DesktopGroupName $group.name #| where {$_.InMaintenanceMode -eq $false}
            $desktopsAvailable = $desktopsTotal | where {$_.InMaintenanceMode -eq $false}
            $inuse = ($desktopsAvailable | Where {$_.summaryState -notmatch "Available" -and $_.summaryState -notmatch "Off"}).count
            $total = $desktopsAvailable.Count

            if ($inuse -gt ($total * (0.85))) {
                
                $temp = New-Object psobject -Property @{
                    InUse = $inuse
                    TotalUsable = $total
                    Total = $DesktopsTotal.count
                    DDC = $ddc
                    DeliveryGroup = $group.name
                }
                $output += $temp
            }
        }
    }
    if ($output.count -eq "0" -and $previousBadList.count -eq "0")
    {
        $newBadList = @()
        $stillbadlist = @()
        $recovered = @()
    } elseif ($output.count -eq "0" -and $previousBadList.count -ne "0") 
    {
        $recovered = $previousBadList | Select DeliveryGroup,DDC            
    }else 
    {
        #Compare output to previousbadlist.  Split into 3 variables
        try {
            $recovered = Compare-Object -ReferenceObject $output -DifferenceObject $previousBadList -Property DDC, DeliveryGroup | where {$_.SideIndicator -eq "=>"} | Select DDC, DeliveryGroup
            $stillbadlist = Compare-Object -ReferenceObject $output -DifferenceObject $previousBadList -Property DDC, DeliveryGroup -IncludeEqual -PassThru | where {$_.SideIndicator -eq "=="} | Select DDC, DeliveryGroup, Total, InUse, TotalUsable
            $newbadlist = Compare-Object -ReferenceObject $output -DifferenceObject $previousBadList -Property DDC, DeliveryGroup -PassThru | where {$_.SideIndicator -eq "<="} | Select DDC, DeliveryGroup, Total, InUse, TotalUsable
        }
        catch {
            $recovered = @()
            $stillbadlist = @()
            $newbadlist = $output
        }
}
    #This becomes the next previousbadlist at runtime
    $allBad += $stillbadlist
    $allBad += $newbadlist
    $allBad | Export-CSV -Path $badFilePath -NoTypeInformation -ErrorAction SilentlyContinue 
}
end {
        $html = @"
        $css
"@
    If ($newbadlist -or $recovered) {         
        #need to make table for new bad
        if ($newBadList) {
            $html += "<h2>New Delivery Groups at 85% Capacity</h2>"
            $html += '<table id ="citrix">'
            $html += "<tr>"
            $html += "<th>Delivery Group</th>"
            $html += "<th>In Use</th>"
            $html += "<th>Total Available</th>"
            $html += "<th>Total</th>"
            $html += "<th>DDC</th>"
            $html += "</tr>"

            foreach ($b in $newBadList) {
                $html += "<tr><td>$($b.DeliveryGroup)</td><td>$($b.InUse)</td><td>$($b.TotalUsable)</td><td>$($b.Total)</td><td>$($b.DDC)</td></tr>"
            }

            $html += "</table>"
        }

        #need to make table to existing bad
        if ($stillbadlist) {
            $html += "<h2>Existing Delivery Groups at 85% Capacity</h2>"
            $html += '<table id ="citrix">'
            $html += "<tr>"
            $html += "<th>Delivery Group</th>"
            $html += "<th>In Use</th>"
            $html += "<th>Total</th>"
            $html += "<th>DDC</th>"
            $html += "</tr>"

            foreach ($c in $stillbadlist) {
                $html += "<tr><td>$($c.DeliveryGroup)</td><td>$($c.InUse)</td><td>$($c.TotalUsable)</td><td>$($c.Total)</td><td>$($c.DDC)</td></tr>"
            }

            $html += "</table>"
        }

        #need to make table for recovered bad
        if ($recovered) {
            $html += "<h2>Recovered Delivery Groups</h2>"
            $html += '<table id ="citrix">'
            $html += "<tr>"
            $html += "<th>Delivery Group</th>"
            $html += "<th>DDC</th>"
            $html += "</tr>"

            foreach ($d in $recovered) {
                $html += "<tr><td>$($d.DeliveryGroup)</td><td>$($d.DDC)</td></tr>"
            }

            $html += "</table>"
        }
        $html += "</body>"
        $html += "</html>"

    $exitEmail= @{
        to = "ToPeople@copmany.com"
        smtp = "SMTP.Company.com"
        body = $html
        bodyasHTML = $true
        from = "No-Reply@Company.com"
        Subject = "Delivery Groups at 85% capacity."
    }    
    Send-MailMessage @exitEmail

    }#end if newbad/recovered
} #end End block