#!/bin/bash
echo ""
echo "Updating database file"
echo ""
FILE_SIZE=$(wget --spider --server-response https://radioid.net/static/user.csv 2>&1 | grep -i Content-Length | awk '{print $2}')
if [ -z "$FILE_SIZE" ]; then
    echo "Downloading..."
    wget -q -O /xlxd/users_db/user.csv https://radioid.net/static/user.csv
else
    echo "File size: $FILE_SIZE bytes"
    wget -q -O - https://radioid.net/static/user.csv | pv --force -p -t -r -b -s "$FILE_SIZE" > /xlxd/users_db/user.csv
fi

# Checks if files exist
if [ ! -f "/xlxd/users_db/users_base.csv" ] || [ ! -f "/xlxd/users_db/user.csv" ]; then
    echo "Error: One or both of the files (users_base.csv or user.csv) were not found."
    exit 1
fi

# Merge user.csv into users_base.csv with the following rules:
#   - RADIO_ID exists, CALLSIGN unchanged : keep full base line
#   - RADIO_ID exists, CALLSIGN changed   : update CALLSIGN/CITY/STATE/COUNTRY, preserve FIRST_NAME and LAST_NAME
#   - RADIO_ID not in base                : insert full line from user.csv
#   - RADIO_ID only in base               : keep full base line
#   - Empty RADIO_ID (repeaters/manual)   : always preserve as-is, never modified
TEMP_FILE=$(mktemp /xlxd/users_db/users_base_tmp.XXXXXX)

awk -F',' -v OFS=',' '
NR==FNR {
    if (NR==1) { header=$0; next }
    if ($1=="") { no_id[NR]=$0; next }
    base[$1] = $0
    next
}
FNR==1 { print header; next }
{
    id=$1
    if (id=="") next
    seen[id] = 1
    if (id in base) {
        split(base[id], b, ",")
        print b[1], $2, b[3], b[4], $5, $6, $7
    } else {
        print $0
    }
}
END {
    for (id in base) {
        if (!(id in seen)) print base[id]
    }
    for (k in no_id) print no_id[k]
}
' /xlxd/users_db/users_base.csv /xlxd/users_db/user.csv \
    | awk -F',' 'NR==1 || $1!="" {print | "sort -t, -k1,1n"} $1=="" {print}' \
    > "$TEMP_FILE"

mv "$TEMP_FILE" /xlxd/users_db/users_base.csv
echo "Merge complete. users_base.csv updated."

# Recreates the updated database
echo "Creating database"
php /xlxd/users_db/create_user_db.php
echo "Database updated successfully!"
echo ""
