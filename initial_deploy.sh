#!/bin/bash

# This script will rename the computer based off of a known asset tag # and then do some other cool stuff with profiles and stuff.
# Before we begin, let's set some values and connect to the server.

# Set terminal window size and color
printf '\e[8;50;100t'

osascript -e "tell application \"Terminal\" to set background color of window 1 to {0,0,0,0}"
osascript -e "tell application \"Terminal\" to set normal text color of window 1 to {0,45000,0,0}"

# disable history characters and old tempfile, do some cleanup tasks  
histchars= 
TMPFILE= 
sudo ntpdate -u time-c.nist.gov

# Set your variables below

## OU where the computer should be placed (specify full path)
OU_LOCATION=
## Which user group/role should be allowed to login
LOCAL_ADMINS=
## Preferred AD domain controller
DEFAULT_PREFERRED_SERVER=
## Domain (@contoso.com)
domain=
## URL to your Munki server
munkiServer=
## File share where CSV containing serial numbers is located at
fileShare=
## Name of Certificate Trust and Enrollment .mobileconfig payloads from macOS Server, hosted on fileShare
TRUST=""
ENROLLMENT=""
## Name of the CSV file (including .csv) where serial numbers and asset tag data is stored
csvName=
## OpenDirectory LDAP Server
openLdapServer=

clear
echo "#=======================================================================================#"
echo "                                                                                         "
echo "                                Computer Deployment Script                               "
echo "     This script will help you prepare a system for an employee by performing Admin      "
echo "       tasks and install applications. Credit to the various devs who contributed.       "
echo "                                                                                         "
echo "                                       Script v1.3                                       "
echo "                                                                                         "
echo "#=======================================================================================#"
echo ""
echo ""
echo ""

echo "Please enter your user credentials, including the '@$domain' portion."
  while [ `echo "$userName" | grep -i -c "@$domain" ` -ne 1 ] ; do
  read -p "Enter username of a person authorized to join the computer to the $domain domain in the format username@$domain: " userName
  done

  read -s -p "Enter the password for user $userName: " userPass
    if [ "$userPass" == "" ]; then
  echo "ERROR: You need to enter a password for $userName - try again!!"
  read -s -p "Enter the password for user $userName: " userPass
    fi

echo ""
echo "OK, let's get started!"
echo ""

echo "Establishing server connection and setting up a temporary folder..."
   TMPFILE=$(mktemp -dt "initial.xxxxx")
   sleep 3
      if [ -d "$TMPFILE" ]; then
        mkdir /Volumes/IT &> /dev/null
        mount -t smbfs //$userName:$userPass@$fileShare /Volumes/IT &> /dev/null
          while [ "$?" = "77" ]; do
          echo ""
          echo "The credentials for $domain\$userName are incorrect. Try again."
          read -p "Enter your $domain username: " userName
          read -s -p "Enter the password for $domain\\$userName: " userPass
          echo ""
            if [ "$userPass" == "" ]; then
              echo "ERROR: You need to enter a password for $domain\\$userName - try again!!"
              read -s -p "Enter the password for $domain\\$userName: " userPass
            fi
           mount -t smbfs //$userName:$userPass@$fileShare /Volumes/IT &> /dev/null
         done
       cp /Volumes/IT/Deploy/Cfg/*.mobileconfig /$TMPFILE
 else
  echo "Temp directory failed to generate. Please run script again."
  exit 1
fi
echo "Done, thanks for waiting!"

# Strip any \r values from the CSV after loop
sed -i '' $'s/\r$//' /Volumes/IT/Deploy/Cfg/$csvName
sleep 3

# Episode 1: The Phantom Script
echo "Starting Computer Rename..."
echo ""

# Get serial from ioreg and assign
serial="$(ioreg -l | grep IOPlatformSerialNumber | sed -e 's/.*\"\(.*\)\"/\1/')" 

# Initialize compName to null
compName=''

# Loop through CSV looking for a match
while IFS=',' read ser loc; do
  if [ "$serial" == "$ser" ]; then
    compName=$loc
    echo "Serial number matched with computer name: $compName"
  fi

done < /Volumes/IT/Deploy/Cfg/$csvName

# If compName is not null, use scutil to rename. Otherwise user must manually rename
if [[ -z $compName ]]; then
  echo "No computer name matches the serial number of your system. Either manually rename the system or update $csvName and re-run the script."
  exit 1

  else
  echo "Setting Host Name to $compName"
  scutil --set HostName "$compName"

  echo "Setting Computer Name to $compName"
  scutil --set ComputerName $compName
  
  echo "Setting Local Host Name to $compName"
  scutil --set LocalHostName "$compName"
  
  echo "Computer Renamed Successfully!"
fi
sleep 2

# flush the DNS cache
sudo killall -HUP mDNSResponder

# Episode 2: Attack of the shell
# We will install the profiles and join the OD + AD server now. At the end, we'll delete the temp folder.
   
if [ -e "$TMPFILE/$TRUST" ]  
then  
  echo "Importing Trust Profile..."  
  profiles -I -f -F "$TMPFILE/$TRUST"
    if [ "$?" -ne "0" ]  
    then  
      echo ""
      echo "Trust profile import failed, please run script again!"  
      exit 1  
    fi    
  echo ""
  echo "Trust profile imported!" 
fi 

if [ -e "$TMPFILE/$ENROLLMENT" ]  
then  
  echo ""
  echo "Importing Enrollment Profile..."  
  profiles -I -f -F "$TMPFILE/$ENROLLMENT"  
    if [ "$?" -ne "0" ]  
    then  
      echo ""
      echo "Auto enrollment failed, will retry on next boot!"  
      exit 1  
    fi  
  echo ""
  echo "Enrollment Profile imported!"
fi  

echo ""

# this will bind the computer to the OD server

echo "Joining $compName to the OD server..."
sudo dsconfigldap -N -a $openLdapServer

# let's also add the computer to the Active Directory server

echo ""
echo "Joining $compName to the AD server $DEFAULT_PREFERRED_SERVER..."
echo ""

sudo dsconfigad -add $domain -username "$userName" -password "$userPass" -computer "$compName" -ou "$OU_LOCATION" -mobile enable -mobileconfirm disable -shell /bin/bash -packetencrypt disable -packetsign disable -preferred $DEFAULT_PREFERRED_SERVER -groups "$LOCAL_ADMINS"

echo "Successfully added $compName to the $domain domain!"

# Episode 3: Revenge of the script
# This section will go through and enable the various settings in System Preferences -> Sharing and enable the users in those

echo "We will now enable necessary network services."
sudo systemsetup -setremoteappleevents on &> /dev/null
sudo systemsetup -setremotelogin on &> /dev/null
cd /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/ &> /dev/null
sleep 2
sudo ./kickstart -activate -configure -access -on -users employee -privs -all -restart -agent -menu &> /dev/null

echo "Waiting for system to build a file we need..."
  sleep 2

echo "Done!"

echo "Adding the employee user and Administrators group to the sharing settings..."
dseditgroup -o edit -a employee -t user com.apple.access_ssh &> /dev/null
dseditgroup -o edit -a Administrators -t group com.apple.access_ssh &> /dev/null
dseditgroup -o create -q com.apple.access_remote_ae &> /dev/null
sleep 2
dseditgroup -o edit -a employee -t user com.apple.access_remote_ae &> /dev/null
echo "Done!"
sleep 2
clear

echo "We will now update the Antivirus definitions. This may take a few minutes..."
/Library/Application\ Support/Symantec/LiveUpdate/LUTool & spinner $!
echo "Done!"
clear

# Episode 4: A New App
# We will install department-specific applications at this time.
echo "########################################################"
echo ""
echo "At this time, you will select the team the user will be"
echo "on so we can start to install some of their software."
echo "You may choose from the following:"
echo ""
echo "0: Do not install ANY addt'l software"
echo "1: Game/Mobile Engineer"
echo "2: QA"
echo "3: MoPub - Community"
echo "4: Designer"
echo "5: BI/User Analytics"
echo ""
echo "########################################################"
echo ""
read -p "Please enter a selection:" DEPARTMENT

echo "Installing Munki Package Manager..."
sudo installer -pkg /Volumes/IT/Deploy/Apps/MunkiTools.pkg -target / &> spinner $!
echo "Done!"

echo "Configuring Munki manifest based on department choice..."
sudo defaults write /Library/Preferences/ManagedInstalls SoftwareRepoURL "http://$munkiServer/munki_repo"
sudo defaults write /Library/Preferences/ManagedInstalls ClientIdentifier "$DEPARTMENT"
echo "Done!"

echo "Munki will now download software for users' computer. This may take a while..."
sudo /usr/local/munki/ManagedInstalls --installonly


while [ "$SUPD" != "y" -a "$SUPD" != "n" ]; do
    echo "Would you like to install OSX software updates?" 
    read -p "W A R N I N G : This may cause your system to reboot automatically. (y/n):" SUPD

if [ "$SUPD" = "y" ]; then
  sudo softwareupdate -a -i 

elif [ "$SUPD" = "n" ]; then
  echo "OK."

else
  read -p "Please enter y or n. (y/n)" SUPD

fi
done

read -p "The script has finished running successfully. It is advised that you reboot your computer at this time. Would you like to reboot? (y/n):" REBOOT
  if [ "$REBOOT" = "y" ]; then
    echo "The system will now reboot in 60 seconds to tidy things up..."
    echo "WARNING: SAVE ALL OPEN WORK!"
    sudo shutdown -r +1 
    exit 0
  else

echo "Script will now exit..."
sleep 2
/usr/bin/srm -mfr "$TMPFILE"  
fi
/usr/bin/srm "$0"
