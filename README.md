Powershell script to auto expand StorSimple volume based on free space
======================================================================

            

Script to auto-expand StorSimple volume based on configurable parameters.


This is intended to run as a scheduled task or job on the file server receiving the iSCSI volume from StorSimple device.


The Input region is where the script input should be entered. Most of that information is available in your classic Azure portal under https://manage.windowsAzure.com under your StorSimple Manager Service - Dashboard and Devices pages.


For more information see [https://superwidgets.wordpress.com/2016/04/01/powershell-script-to-auto-expand-storsimple-volume-based-on-amount-of-free-space/](https://superwidgets.wordpress.com/2016/04/01/powershell-script-to-auto-expand-storsimple-volume-based-on-amount-of-free-space/)


Author: Sam Boutros - 29 March, 2016 - v1.0


Here's a code snippet:


 

 

**Possible future enhancements to this script include:**


  *  Rewrite the script as a function so that it can handle several volumes 
  *  Rewrite the script to use Powershell remoting, so that it does not have to run on the file server.

  *  Add functionality to detect if the target file server is a member of a failover cluster, and to automatically target the owner node.


    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
