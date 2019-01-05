#!/bin/bash
#Usage is ./single-user-wp-cron.sh CPANEL_USERNAME SLEEP_VALUE
#where SLEEP_VALUE is the time to sleep before executing the cron
#Written by Tim Duncan for Servers Australia - Dec 31 2018
#This script scans the docroot for the domain CPANEL_USERNAME which is passed to this script as the first argument. It finds
#any wp-config.php files, and sets define('DISABLE_WP_CRON', 'true'); inside the file.
#It then adds a crontab entry (echo "*/5 * * * * cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1) to the users crontab

#This function takes TWO arguments - $1 = The System username who's crontab will be modified, $2 = List of Paths to the wp-config.php file
if [ -z "$1" ]; then
	echo No user set - exiting;
	exit 1;
else
	echo Executing for user $1
fi
REGEX='^[0-9]+$'
if ! [[ $2 =~ $REGEX ]]; then
	echo "$2 is not a number"
	echo using default sleep of 0
	SLEEP=0
else
	echo Setting sleep to $2
	SLEEP=$2
fi
function ModifyCrontab() {
	CPANEL_USERNAME="$1"
	WP_CONFIG_PATH="$2"
	#For each path listed in WP_CONFIG_PATH:
	while read FILE_PATH; do
		if [ -n "$FILE_PATH" ]; then
			#Get the folder name (this strips the trailing /wp-config.php out of the string)
			FOLDER=`dirname "$FILE_PATH"`
			#Lists the current crontab, appends the new cronjob, sorts and removes duplicates, reinstalls the crontab - and makes sure to work even with an empty crontab
			echo "Adding */5 * * * * sleep "$SLEEP"; cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1 to "$CPANEL_USERNAME"'s crontab"
			( (crontab -l -u "$CPANEL_USERNAME" 2>/dev/null || echo "") ; echo "*/5 * * * * sleep "$SLEEP"; cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1") | sort -u | crontab -u "$CPANEL_USERNAME" -
		else
			echo "ERROR: ModifyCrontab was passed a null variable!"
		fi
	done <<< "$WP_CONFIG_PATH"
}

#This function takes one argument - STRING - a path or lists of paths to the wp-config.php file/s to modify. One on each line.
function ModifyWPConfig() {
	#Loop through each line of the first argument variable
	while read FILE_PATH; do
		#Check that the file exists
		if [ -e $FILE_PATH ]; then
			grep -i "DISABLE_WP_CRON" "$FILE_PATH" > /dev/null
			#If there is already a DISABLE_WP_CRON line found, then replace it
			if [ $? -eq 0 ]; then
				echo "Modifying existing DISABLE_WP_CRON entry inside $FILE_PATH."
				#take a backup of the current wp-config.php and change the relevent line
				sed -i.bak "s/.*DISABLE_WP_CRON.*/define('DISABLE_WP_CRON', 'true');/gI" "$FILE_PATH"
			else
				#If there is NOT a DISABLE_WP_CRON line found, then add it above the first define statement
				#Append the disable wp cron line to wp-config.php, before the first define statement
				echo "Adding DISABLE_WP_CRON statement to $FILE_PATH"
				sed -i.bak "0,/define/s//define('DISABLE_WP_CRON', 'true')\;\ndefine/" "$FILE_PATH"
			fi
		else
			echo "ERROR: FILE DOESN'T EXIST: $FILE_PATH"
		fi
	done <<< "$1"
}

#This function takes a cPanel username and list of Paths to wp-config.php, and executes the other functions
function DisableWpCron() {
	USERNAME="$1"
	CONFIG_PATHS="$2"
	#Only if CONFIG_PATHS is set:
	if [ -n "$CONFIG_PATHS"  ]; then
		#echo "wp-config.php files found:"
		#echo "$CONFIG_PATHS"
		#Insert or Modify the WP_CRON line in to each wp-config.php file
		ModifyWPConfig "$CONFIG_PATHS"
		#Add the relevent crontab entry to the cPanel username's crontab
		ModifyCrontab "$USERNAME" "$CONFIG_PATHS"
	else
		echo "ERROR: DisableWpCron was passed a null variable."
	fi
}

#Main
FIRST_RUN="YES"
#Take a backup of the system crontabs
echo "Backing up /var/spool/cron/ to /root/cronbackups/"
rsync -avhxq /var/spool/cron/ /root/cronbackups/
USERDATA=`grep "$1" /etc/userdatadomains`
while read LINE; do
	DOMAIN=`echo "$LINE" | cut -d ':' -f1`
	DOCROOT=`echo "$LINE" | cut -d '=' -f9`
	USERNAME=`echo "$LINE" | cut -d '=' -f1 | cut -d ':' -f2 | xargs -I {} echo {}`
	#Find any wp-config.php files inside the document root
	CONFIG_PATHS=`find "$DOCROOT" -type f -name wp-config.php`
	echo -e "\nDomain: $DOMAIN"
	echo "User: $USERNAME"
	echo "Docroot: $DOCROOT"
	if [ -z "$CONFIG_PATHS" ]; then
		echo "No wp-config.php files detected inside $DOCROOT. SKIPPING."
		continue;
	else
		echo -e "Detected wp-config.php files:\n$CONFIG_PATHS"
	fi
	#if it's the first run, don't do the docroot check below
	if [ "$FIRST_RUN" = "YES" ]; then
		#echo FIRST_RUN
		DisableWpCron "$USERNAME" "$CONFIG_PATHS"
		FIRST_RUN='NO'
	else
		#echo Not FIRST_RUN
		#Check over the DOCROOTS_CHECKED list, and only proceed if we haven't scanned the DOCROOT already
		while read DOCROOT_CHECK; do
			#echo Entering DOCROOT_CHECK loop
			#echo DOCROOTS_CHECKED="$DOCROOTS_CHECKED"
			#make sure DOCROOT_CHECK is set:
			if [ -n "$DOCROOT_CHECK" ]; then
				#echo "DOCROOT_CHECK variable is set: $DOCROOT_CHECK"
				#check to see if docroot has already been checked
				ALREADY_CHECKED="NO"
				if [ "$DOCROOT" = "$DOCROOT_CHECK" ]; then
					echo "$DOCROOT has already been scanned. SKIPPING."
					ALREADY_CHECKED="YES"
				fi
			else
				echo "ERROR: DOCROOT_CHECK variable is NOT set"
			fi
		done <<< "$DOCROOTS_CHECKED"

		if [ "$ALREADY_CHECKED" = "NO" ]; then
			#echo "Executing DisableWpCron $USERNAME $CONFIG_PATHS"
			DisableWpCron "$USERNAME" "$CONFIG_PATHS"
		fi
	fi
	#Add the DOCROOT to the DOCROOTS_CHECKED variable
	DOCROOTS_CHECKED_CACHE=`echo "$DOCROOTS_CHECKED"; echo "$DOCROOT"`
	#echo "DOCROOTS_CHECKED_CACHE: $DOCROOTS_CHECKED_CACHE"
	DOCROOTS_CHECKED=`echo "$DOCROOTS_CHECKED_CACHE" | uniq | sed '/^$/d' -`
	#echo -e "DOCROOTS_CHECKED: $DOCROOTS_CHECKED\n"
done <<< "$USERDATA"
