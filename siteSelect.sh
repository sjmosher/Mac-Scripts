#!/bin/bash

### Sam Mosher, Social Sciences IT
### University of California, Davis. All rights reserved.
### This script will run an interactive shell which allows an API authorized Jamf admin to change the site of a system.
### You can also move a computer to a new site.
### At the end, it will prompt you to run the site-specific deployment - any policies matching {siteName}_enroll.

# Set terminal window size and color
printf '\e[8;30;90t'

osascript -e "tell application \"Terminal\" to set background color of window 1 to {0,0,0,0}"
osascript -e "tell application \"Terminal\" to set normal text color of window 1 to {0,45000,0,0}"

echo ""
echo ""
echo ""
clear
echo "#=======================================================================================#"
echo "                                                                                         "
echo "          ___   ______________________   ____  ___________ __ ____________  ____         "
echo "         /   | / ____/ ____/  _/ ____/  / __ \/ ____/ ___// //_/_  __/ __ \/ __ \        "
echo "        / /| |/ / __/ / __ / // __/    / / / / __/  \__ \/ ,<   / / / / / / /_/ /        "
echo "       / ___ / /_/ / /_/ // // /___   / /_/ / /___ ___/ / /| | / / / /_/ / ____/         " 
echo "      /_/  |_\____/\____/___/_____/  /_____/_____//____/_/ |_|/_/  \____/_/              "
echo "                                                                                         "
echo "                                                                                         "
echo "                                DEPARTMENT SELECTOR SCRIPT                               "
echo "       Use your JSS username and password to update the SITE for this computer           "
echo "                                                                                         "
echo "                                       Script v1.0                                       "
echo "   The Regents of the University of California, Davis campus. All rights reserved.       "                  
echo "                                                                                         "
echo "#=======================================================================================#"
echo ""
echo ""
echo ""

# set some global vars
httpUnauth="HTTP/1.1 401 Unauthorized"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"

# if [[ $HTTPSTATUS != $HTTPOK ]] ; then
echo "Please enter your JSS Username. This can be your LDAP credentials."
  while [ -z "$jssUser" ] ; do
    read -p "Enter your JSS Username: " jssUser
  done
  read -s -p "Enter the password for user $jssUser: " jssPassword
    if [ "$jssPassword" == "" ]; then
      echo "ERROR: You need to enter a password for $jssUser - try again!!"
        read -s -p "Enter the password for user $jssUser: " jssPassword
    fi

# checks api authorization
httpStatus="$(curl -IL -s -u $jssUser:"$jssPassword" -X GET https://jss.ucdavis.edu:8443/JSSResource/sites -H "Accept: application/xml" | grep HTTP)"

if [[ $httpStatus == "$httpUnauth"* ]]; then
  echo ""
  echo "API connection failed - UNAUTHORIZED. Possible typo in credentials. Please run script again."
  exit 1
fi

# let's continue now that auth is OK

echo ""
echo "OK, let's get started!"
echo "Retrieving list of Sites from jss.ucdavis.edu..."

# set site variable
allSites="$(curl -s -u $jssUser:"$jssPassword" -X GET https://jss.ucdavis.edu:8443/JSSResource/sites -H "Accept: application/xml" | xpath "/sites/site/name" | sed -e 's/<name>//g;s/<\/name>/ /g')"

# prompt user to choose Site

echo "Please select a site for computer $serialNumber:"
echo ""
PS3="Please enter the site number or type 'cancel' to quit:"

select siteChoice in $allSites
do
  # leave the loop if the user says 'cancel'
  shopt -s nocasematch
    if [[ "$REPLY" =~ "cancel" ]]; then 
      echo "Script cancelled..."
      exit 0
    fi
  shopt -u nocasematch

    # complain if no site was selected, and loop to ask again
    if [[ "$siteChoice" == "" ]]
    then
        echo "'$REPLY' is not a valid selection"
        continue
    fi
  break
done

echo "You selected site $siteChoice. Contacting JSS to submit changes for computer $serialNumber ..."

# set XML for API call and PUT to JSS
apiSiteData="$(echo "<computer><general><site><name>$siteChoice</name></site></general></computer>")"
curl -s -u $jssUser:"$jssPassword" -X PUT -H "Content-Type: text/xml" -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiSiteData" https://jss.ucdavis.edu:8443/JSSResource/computers/serialnumber/$serialNumber > /dev/null
echo "Done submitting changes to JSS!"
echo ""

# run site deployment script
echo "Would you like to run your site deployment scripts?"
PS3='Please select an option: '
options=("Yes" "No")
select opt in "${options[@]}"
do
    case $opt in
        "Yes")
            echo "OK, running deployment scripts for site $siteChoice..."
            sudo jamf policy -trigger $siteChoice"_enroll"
            break
            ;;
        "No")
            echo "OK, exiting Site Selection script..."
            break
            ;;
        *) echo invalid option;;
    esac
done
exit 0
