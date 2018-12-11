#!/bin/bash
EXCLUDECPUSER='arinex'
SCANMAXDEPTH=2

while read LINE; do
    DOMAIN=`echo "$LINE" | cut -d ':' -f1`
    PUBLICHTML=`echo "$LINE" | cut -d '=' -f9`
    CPANELUSERNAME=`echo "$LINE" | cut -d '=' -f1 | cut -d ':' -f2 | xargs -I {} echo {}`
    echo "$DOMAIN", with cPanel username "$CPANELUSERNAME" has Public Html directory of: "$PUBLICHTML"
    #Find wp-config.php inside the public_html directory
    WPCONFIGPATH=`find "$PUBLICHTML" -maxdepth "$SCANMAXDEPTH" -type f -name wp-config.php`
    #Todo: Add support for multiple excludes.
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
                    echo Setting WP_CRON = FALSE inside "$WPCONFIGPATH"
                    echo
            fi
    fi
done < /etc/userdatadomains
