Set-StrictMode -Version 2 -Verbose
$ErrorActionPreference = 'Stop'

function funcParseHtmlDirListingLineToObject( [System.Net.HttpWebResponse] $oHttpWebResponse, [string] $sHtml ) {
    <#  .DESCRIPTION
            Parse a single line of HTML that contains a directory listing
        .OUTPUTS
            Custom object with a minimum of .matched = $true/$false
    #>
    switch ($oHttpWebResponse.Server) {
        {($_ -eq 'Microsoft-IIS/8.5') -or 
         ($_ -eq 'Microsoft-IIS/7.5') } {
            #IIS 8.5    Wednesday, February 22, 2017  3:22 PM        &lt;dir&gt; <A HREF="/Dell/">Dell</A>
            #IIS 8.5    Monday, August 29, 2016  3:02 PM     58596186 <A HREF="/my_dir/Installer/Setup.exe">Setup.exe</A>
            #IIS 7.5    Thursday, March 23, 2017 12:53 PM        &lt;dir&gt; <A HREF="/WSUS/Updates/">Updates</A><

            $aRegPrep = @()
            $aRegPrep += '(?<fulldatetime>'  # Start group for full datetime
            $aRegPrep += '(?<weekday>Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)'
            $aRegPrep += '\,\s'
            $aRegPrep += '(?<month>January|February|March|April|May|June|July|August|September|November|December)'
            $aRegPrep += '\s'
            $aRegPrep += '(?<day>\d{1,2})\,\s(?<year>\d{4})\s{1,2}(?<time>\d{1,2}\:\d{1,2}\s[AP]M)'
            $aRegPrep += ')'  # Close group for full datetime
            $aRegPrep += '\s*?((?<filesize>\d{1,12})|(?<dirgrp>\&lt\;(?<type>dir)\&gt\;))'
            $aRegPrep += '\s'
            $aRegPrep += '\<A HREF\=\"(?<hreflink>\/.*)\"\>.*?\<\/A\>'
            $regLine = [regex] ($aRegPrep -join '')
            break
        }
        default {
            $textOut1 = "Unknown web server type: '{0}' " -f @($oHttpWebResponse.Server)
            throw [System.ArgumentException] $textOut1
        }
    } # End switch
    $matches = $null
    $sHtml -match $regLine | Out-Null
    $oReturned = New-Object -TypeName System.Management.Automation.PSObject
    $oReturned = $oReturned | Select matched,fulldatetime,filesize,type,hreflink
    if ( $null -eq $matches ) {
        $oReturned.matched = $false
        return ,$oReturned
    }
    $oReturned.matched = $true
    try {
        if ( $matches.filesize ) {
            $oReturned.filesize = [int] $matches.filesize
            $oReturned.type = 'file'
        } else {
            $oReturned.type = 'dir'
        }
    } catch {
        $oReturned.type = 'dir'
    }
    $oReturned.fulldatetime = [datetime] $matches.fulldatetime  # All other time info can be extracted from this
    $oReturned.hreflink = $matches.hreflink
    return ,$oReturned
} # End funcParseHtmlDirListingLineToObject

function funcGetSingleWebPage([string] $sUrl) {
    <#  .DESCRIPTION
            Get the HTML for the specified URL
        .PARAMERTER sUrl
            URL location to retrieve
        .OUTPUTS
            Custom object with attributes .shtml (string) and .oHttpWebResponse (Response Object)
        .NOTES
            PS v2 compatible. Supports HTTPS.
    #>
    $oHttpWebRequest = [System.Net.HttpWebRequest]::Create($sUrl)
    $oHttpWebRequest.KeepAlive = $true
    $oHttpWebResponse = $oHttpWebRequest.GetResponse()
    if ( $oHttpWebResponse.StatusCode.value__ -ne 200) {
        throw 'Bad response from web server'
    }
    $oStream = $oHttpWebResponse.GetResponseStream()
    $oStreamDest = New-Object System.IO.StreamReader($oStream)
    $sHtml = $oStreamDest.ReadToEnd()
    $oStreamDest.Close()
    $oStream.Close()
    $oStream.Dispose()
    $oReturned = New-Object -TypeName System.Management.Automation.PSObject
    $oReturned = $oReturned | Select oHttpWebResponse,sHtml
    $oReturned.oHttpWebResponse = $oHttpWebResponse
    $oReturned.sHtml = $sHtml
    return ,$oReturned
} # End funcGetSingleWebPage

function funcGetRecursiveWebDirListing([string] $sUrl, [string] $sDomainRoot='') {
    <#  .DESCRIPTION
            Get a recursive listing of every file on the server starting at $sUrl
        .PARAMERTER sUrl
            Starting point of the recursion.  Required during first call
        .PARAMERTER sDomainRoot
             The root URL of the recursion.  This is set to $sUrl domain by default.
        .OUTPUTS
            Array of strings. Each string is the full path listing for a file on the server
    #>
    if ( $sDomainRoot.length -eq 0 ) {  # Fix up our domain root
        $oParsedUrl = [System.Uri] $sUrl
        $sDomainRoot = @($oParsedUrl.Scheme,'://',$oParsedUrl.Authority) -join ''
    }
    $oSingleReqResult = funcGetSingleWebPage $sUrl
    $aHtml = @([regex]::Split($oSingleReqResult.sHtml,'br>'))  # Need to update if not on IIS?
    $aFileListing = @()
    foreach ( $sLine in $aHtml ) {
        $oParsedLine = funcParseHtmlDirListingLineToObject $oSingleReqResult.oHttpWebResponse $sLine
        if ( $oParsedLine.matched ) {
            # Note that the paths are relative to the domain root
            if ( $oParsedLine.type -eq 'file' ) {
                $aFileListing += @($sDomainRoot.Trim('/'),$oParsedLine.hreflink) -join ''
            }
            if ( $oParsedLine.type -eq 'dir' ) {  # Recursively lookup this
                $sUrlTemp = @($sDomainRoot.Trim('/'),$oParsedLine.hreflink) -join ''
                # $aFileListing += $sUrlTemp  # Uncomment to include directories in the final listing
                $aFileListing += funcGetRecursiveWebDirListing $sUrlTemp $sDomainRoot
            }
        }
    } # End ForEach-Object
    return ,$aFileListing
} # End funcGetRecursiveWebDirListing

#--------------------------------------------------------------------------------
# Regular usage, no root supplied
$sUrl = 'https://myfileshare.domain1.com/'
$aFinal = funcGetRecursiveWebDirListing $sUrl
# $aFinal is an Array of strings, one entry for each file found
# https://myfileshare.domain1.com/Dell/PowerEdge_2950/WN64_7.10.18.EXE
# https://myfileshare.domain1.com/directory1/Config/options.xml
# https://myfileshare.domain1.com/directory1/Installer/Setup.exe
# https://myfileshare.domain1.com/directory2/SchedTask/upload.xml
# https://myfileshare.domain1.com/web.config

#--------------------------------------------------------------------------------
# Regular usage, subdirectory start, no root supplied
$sUrl = 'https://myfileshare.domain1.com/directory1'
$aFinal = funcGetRecursiveWebDirListing $sUrl
# $aFinal
# https://myfileshare.domain1.com/directory1/Config/options.xml
# https://myfileshare.domain1.com/directory1/Installer/Setup.exe

