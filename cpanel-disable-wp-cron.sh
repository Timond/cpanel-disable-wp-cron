#!/bin/bash
EXCLUDECPUSER='arinex'
SCANMAXDEPTH=2
#This loop goes through each domain listed in /etc/userdatadomains which should list every cPanel domain, and subdomain on the server.
while read LINE; do
 DOMAIN=`echo "$LINE" | cut -d ':' -f1`
 PUBLICHTML=`echo "$LINE" | cut -d '=' -f9`
 CPANELUSERNAME=`echo "$LINE" | cut -d '=' -f1 | cut -d ':' -f2 | xargs -I {} echo {}`
 echo "$DOMAIN", with cPanel username "$CPANELUSERNAME" has Public Html directory of: "$PUBLICHTML"
 #Find wp-config.php inside the public_html directory
 WPCONFIGPATH=`find "$PUBLICHTML" -maxdepth "$SCANMAXDEPTH" -type f -name wp-config.php`

 if [ "$CPANELUSERNAME" = "$EXCLUDECPUSER" ]; then
  echo Detected "$EXCLUDECPUSER" as cPanel Username - This user is excluded - Skipping
  echo
 else
  #Check if the wp-config.php path is empty
  if [ -z "$WPCONFIGPATH" ]; then
      echo wp-config.php not found - skipping
      echo
  else
      echo wp-config.php path found = "$WPCONFIGPATH"
      echo Checking for existing DISABLE_WP_CRON line inside "$WPCONFIGPATH"
      grep -i "DISABLE_WP_CRON" "$WPCONFIGPATH"
      if [ $? -eq 0 ]; then
    echo "DISABLE_WP_CRON" line found.
    echo "$WPCONFIGPATH" backed up to "$WPCONFIGPATH".bak
    #take a backup of the current wp-config.php and change the relevent line
    sed -i.bak "s/.*DISABLE_WP_CRON.*/define('DISABLE_WP_CRON', 'true');/gI" "$WPCONFIGPATH"
      else
    echo "DISABLE_WP_CRON" line NOT found - Adding it to the end of "$WPCONFIGPATH"
    echo "$WPCONFIGPATH" backed up to "$WPCONFIGPATH".bak
    #Copy wp-config.php to wp-config.php.bak
    cp "$WPCONFIGPATH"{,.bak}
    #Append the disable wp cron line to wp-config.php
    echo "define('DISABLE_WP_CRON', 'true');" >> "$WPCONFIGPATH"
      fi
      #Get the folder name (this strips the trailing /wp-config.php out of the string)
      FOLDER=`dirname "$WPCONFIGPATH"`
      echo "Adding */5 * * * * cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1" to ""$CPANELUSERNAME" crontab"
      #Lists the current crontab, appends the new cronjob, sorts and removes duplicates, reinstalls the crontab - and makes sure to work even with an empty crontab      
      ( (crontab -l -u "$CPANELUSERNAME" 2>/dev/null || echo "")  ; echo "*/5 * * * * cd ""$FOLDER""; php -q wp-cron.php >/dev/null 2>&1") | sort -u - | crontab -u "$CPANELUSERNAME" -
      echo
  fi
 fi

done < /etc/userdatadomains
