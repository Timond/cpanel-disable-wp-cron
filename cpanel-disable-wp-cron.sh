#!/bin/bash

#Written by Tim Duncan for Servers Australia - Dec 31 2018
#This script scans the docroot for all domains listed in /etc/userdatadomains on a cPanel server, finds
#any wp-config.php files, and sets define('DISABLE_WP_CRON', 'true'); inside the file.
#It then adds a crontab entry (echo "*/5 * * * * cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1) to the users crontab

#This function takes TWO arguments - $1 = The System username who's crontab will be modified, $2 = List of Paths to the wp-config.php file
function ModifyCrontab() {
	CPANELUSERNAME="$1"
	WPCONFIGPATH="$2"
	#For each path listed in WPCONFIGPATH:
	while read FILEPATH; do
		if [ -n "$FILEPATH" ]; then
			#Get the folder name (this strips the trailing /wp-config.php out of the string)
			FOLDER=`dirname "$FILEPATH"`
			#Lists the current crontab, appends the new cronjob, sorts and removes duplicates, reinstalls the crontab - and makes sure to work even with an empty crontab
			echo "Adding */5 * * * * cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1 to "$CPANELUSERNAME"'s crontab"
			( (crontab -l -u "$CPANELUSERNAME" 2>/dev/null || echo "") ; echo "*/5 * * * * cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1") | sort -u | crontab -u "$CPANELUSERNAME" -
		else
			echo "ERROR: ModifyCrontab was passed a null variable!"
		fi
	done <<< "$WPCONFIGPATH"
}

#This function takes one argument - STRING - a path or lists of paths to the wp-config.php file/s to modify. One on each line.
function ModifyWPConfig() {
	#Loop through each line of the first argument variable
	while read FILEPATH; do
		#Check that the file exists
		if [ -e $FILEPATH ]; then
			grep -i "DISABLE_WP_CRON" "$FILEPATH" > /dev/null
			#If there is already a DISABLE_WP_CRON line found, then replace it
			if [ $? -eq 0 ]; then
				echo "Modifying existing DISABLE_WP_CRON entry inside $FILEPATH."
				#take a backup of the current wp-config.php and change the relevent line
				sed -i.bak "s/.*DISABLE_WP_CRON.*/define('DISABLE_WP_CRON', 'true');/gI" "$FILEPATH"
			else
				#If there is NOT a DISABLE_WP_CRON line found, then add it above the first define statement
				#Append the disable wp cron line to wp-config.php, before the first define statement
				echo "Adding DISABLE_WP_CRON statement to $FILEPATH"
				sed -i.bak "0,/define/s//define('DISABLE_WP_CRON', 'true')\;\ndefine/" "$FILEPATH"
			fi
		else
			echo "ERROR: FILE DOESN'T EXIST: $FILEPATH"
		fi
	done <<< "$1"
}

#This function takes a cPanel username and list of Paths to wp-config.php, and executes the other functions
function DisableWpCron() {
	USERNAME="$1"
	CONFIGPATHS="$2"
	#Only if configpaths is set:
	if [ -n "$CONFIGPATHS"  ]; then
		#echo "wp-config.php files found:"
		#echo "$CONFIGPATHS"
		#Insert or Modify the WP_CRON line in to each wp-config.php file
		ModifyWPConfig "$CONFIGPATHS"
		#Add the relevent crontab entry to the cPanel username's crontab
		ModifyCrontab "$USERNAME" "$CONFIGPATHS"
	else
		echo "ERROR: DisableWpCron was passed a null variable."
	fi
}

#Main
FIRSTRUN="YES"
#Take a backup of the system crontabs
echo "Backing up /var/spool/cron/ to /root/cronbackups/"
rsync -avhxq /var/spool/cron/ /root/cronbackups/
#Loop through /etc/userdatadomains, and for each domain, get the cPanel username, and document root.
while read LINE; do
	DOMAIN=`echo "$LINE" | cut -d ':' -f1`
	DOCROOT=`echo "$LINE" | cut -d '=' -f9`
	USERNAME=`echo "$LINE" | cut -d '=' -f1 | cut -d ':' -f2 | xargs -I {} echo {}`
	#Find any wp-config.php files inside the document root
	CONFIGPATHS=`find "$DOCROOT" -type f -name wp-config.php`
	echo -e "\nDomain: $DOMAIN"
	echo "User: $USERNAME"
	echo "Docroot: $DOCROOT"
	if [ -z "$CONFIGPATHS" ]; then
		echo "No wp-config.php files detected inside $DOCROOT. SKIPPING."
		continue;
	else
		echo -e "Detected wp-config.php files:\n$CONFIGPATHS"
	fi
	#if it's the first run, don't do the docroot check below
	if [ "$FIRSTRUN" = "YES" ]; then
		#echo Firstrun
		DisableWpCron "$USERNAME" "$CONFIGPATHS"
		FIRSTRUN='NO'
	else
		#echo Not Firstrun
		#Check over the DOCROOTSCHECKED list, and only proceed if we haven't scanned the DOCROOT already
		while read DOCROOTCHECK; do
			#echo Entering DOCROOTCHECK loop
			#echo DOCROOTSCHECKED="$DOCROOTSCHECKED"
			#make sure DOCROOTCHECK is set:
			if [ -n "$DOCROOTCHECK" ]; then
				#echo "Docrootcheck variable is set: $DOCROOTCHECK"
				#check to see if docroot has already been checked
				ALREADYCHECKED="NO"
				if [ "$DOCROOT" = "$DOCROOTCHECK" ]; then
					echo "$DOCROOT has already been scanned. SKIPPING."
					ALREADYCHECKED="YES"
				fi
			else
				echo "ERROR: Docrootcheck variable is NOT set"
			fi
		done <<< "$DOCROOTSCHECKED"

		if [ "$ALREADYCHECKED" = "NO" ]; then
			#echo "Executing DisableWpCron $USERNAME $CONFIGPATHS"
			DisableWpCron "$USERNAME" "$CONFIGPATHS"
		fi
	fi
	#Add the DOCROOT to the DOCROOTSCHECKED variable
	DOCROOTSCHECKEDCACHE=`echo "$DOCROOTSCHECKED"; echo "$DOCROOT"`
	#echo "DOCROOTSCHECKEDCACHE: $DOCROOTSCHECKEDCACHE"
	DOCROOTSCHECKED=`echo "$DOCROOTSCHECKEDCACHE" | uniq | sed '/^$/d' -`
	#echo -e "DOCROOTSCHECKED: $DOCROOTSCHECKED\n"
done < /etc/userdatadomains
