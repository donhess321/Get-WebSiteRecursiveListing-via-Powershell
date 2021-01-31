# Get-WebSiteRecursiveListing-via-Powershell

Get a recursive listing of every file (and directories as as an option) on a web server. The output is an array of strings. Each string is the full path listing for a file on the server. The current version support IIS 8.5/7.5 directory listing parsing to an object but can be expanded to other web servers.  The HTML parsing is done through a regex.  I wrote this because I needed to get a HTTPS directory layout in Powershell v2 even though better options are avaiable in v3-v5.  Note the web server needs to have directory browsing enabled.

I decided to use the .NET assemblies because it allows running the script from a server, where Invoke-WebRequest would not.  When using Invoke-WebRequest, Internet Explorer is called to do the parsing of the HTML to objects.  The default IE settings on a server do not allow this parsing and you receive multiple popup windows about adding a site to the allowed list.  I would rather leave the IE settings as they are.
 
This is a reposting from my Microsoft Technet Gallery.
