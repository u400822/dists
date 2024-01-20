#!/usr/bin/env bash

echo "Jai ho"
base_dir=$(realpath "$(dirname "$0")")
owner="u400822"
repo="huy-packages"
asset_json=$(mktemp /tmp/json.XXXXXXX)
gh api -H "Accept: application/vnd.github.v3+json"  https://api.github.com/repos/$owner/$repo/releases > $asset_json


if jq -r '.[] | select(.tag_name=="0.1") | .assets[].name' $asset_json | grep -G ".tar$";then
    echo "Jai ho. we got some unprocessed debfile."
    if $base_dir/dist_handler.sh;then
        $base_dir/remote_handler.sh
    else
        exit 1
    fi
else
    echo "Jai ho. We got sign"
    chmod +x $base_dir/dist_handler_sign.sh
    $base_dir/dist_handler_sign.sh
fi 


