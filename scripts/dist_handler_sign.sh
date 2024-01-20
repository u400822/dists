#!/usr/bin/env bash
set -e -o pipefail
shopt -s extglob
BASE_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
POOL_DIR="$(dirname "$BASE_DIR")/pool"
PROCESSED_DEB=$BASE_DIR/processed_deb
mkdir -p $PROCESSED_DEB
echo $POOL_DIR
Dists_DIR="$(dirname "$BASE_DIR")/dists"
REPO_JSON="$(dirname "$BASE_DIR")/repo.json"
arch_array=("aarch64" "arm" "i686" "x86_64")
components_array=($(jq -r .[].name  $REPO_JSON | tr '\n' ' '))
# Info being added into release file
ORIGIN="u400822"
Suite="huy-packages"
Codename="huy-packages"
Architectures="aarch64 arm i686 x86_64"
Components=$(for i in "${components_array[@]}";do echo -n "$i ";done)
Description="Huy packages"
remove_archive_from_temp_gh() {
    echo "removing temporay archives"
    # remove only which has download. it wont take gurantee of succesfully processed. if some archives
    # not processed successfully. then most probably issues with archive itself.
    # However repository consistency checker will catch any unsuccesful checks.
    cd $BASE_DIR
    for temp in ./*.tar;do
        if gh release delete-asset -R github.com/$owner/huy-packages $tag "$(basename $temp)" -y;then

            echo "$temp removed!!"
        else
            echo "Error while removing $temp"
        fi
    done
}
commit() {
    pushd $(dirname $BASE_DIR)
    echo "pushing changes"
    if [[ $(git status --porcelain) ]]; then
        git add .
        git commit -m "Updated $list_updated_packages"
        git push
        remove_archive_from_temp_gh
    fi
}
create_dist_structure() {
    echo "Creating dist structure"
    # remove all files and dir in dists.
    rm -rf $Dists_DIR
    mkdir -p $Dists_DIR
    mkdir -p $POOL_DIR
    mkdir -p $Dists_DIR/$Suite
    ## component dir.
    for comp in "${components_array[@]}";do
        mkdir -p $Dists_DIR/$Suite/$comp 
        mkdir -p $Dists_DIR/$Suite/$comp/binary-{aarch64,arm,i686,x86_64}
        ## pool direcectory if not exist.
        mkdir -p $POOL_DIR/$comp
    done



}

create_packages() {
    echo "creating package file. "
    for comp in "${components_array[@]}";do
        echo "creating packages for $comp components"
        cd $POOL_DIR/$comp
        for arch in "${arch_array[@]}";do
            echo $arch
            echo $(pwd)
            count_deb_metadata_file=$(find . -name "*[$arch|all].deb" 2> /dev/null | wc -l)
            echo "$count_deb_metadata_file"
            if [[ $count_deb_metadata_file == 0 ]];then
                echo "continue"
                continue
            fi
            echo "$(pwd) $comp"
            cat ./*{$arch,all}.deb 2>/dev/null >| $Dists_DIR/$Suite/$comp/binary-${arch}/Packages || true

            gzip -9k $Dists_DIR/$Suite/$comp/binary-${arch}/Packages
            echo "packages file created for $comp $arch"
        done
    done
}

add_general_info() {
    release_file_path=$1
    date_=$(date -uR)
    Arch=$2
    if [ $Arch == "all" ];then
        Arch=$Architectures
    fi
    cat > $release_file_path <<-EOF
Origin: $ORIGIN $Codename
Label: $ORIGIN $Codename
Suite: $Suite
Codename: $Codename
Date: $date_
Architectures: $Arch
Components: $Components
Description: $Description
EOF
}

generate_release_file() {
    r_file=$Dists_DIR/$Suite/Release
    rm -f $r_file
    touch $r_file
    cd $Dists_DIR/$Suite

    # add general info in main release file
    add_general_info $r_file "all"
    sums_array=("MD5" "SHA1" "SHA256" "SHA512")
    
    for sum in "${sums_array[@]}";do
        case $sum in
            MD5) 
                checksum=md5sum
                ;;
            SHA1)
                checksum=sha1sum
                ;;
            SHA256)
                checksum=sha256sum
                ;;
            SHA512)
                checksum=sha512sum
                ;;
            *)
                echo '...'
                exit 1
        esac
        echo "processing $sum"
        echo "${sum}:" >> $r_file
        for file in $(find $Components -type f);do
            generated_sum=$($checksum $file | cut -d' ' -f1 )
            filename_and_size=$(wc -c $file)
            echo " $generated_sum $filename_and_size" >> $r_file
            done
    done
            

}
sign_release_file() {
    cd $Dists_DIR/$Suite
    if [[ -n "$SEC_KEY" ]]; then
        echo "Importing key"
        if echo -n "$SEC_KEY" | base32 --decode | gpg --import --batch --yes;then
              echo "*********key imported successfully********"
        else
            echo "Issues while importing private key"
            exit 1
        fi

    fi
    echo "Signing Release file"
    gpg --passphrase "$(echo -n $SEC_PASS | base32 --decode)" --batch --yes --pinentry-mode loopback -u CA3D655ADBDBB49C3912F8F4F7F54014307A2954 -bao ./Release.gpg Release
    gpg --passphrase "$(echo -n $SEC_PASS | base32 --decode)" --batch --yes --pinentry-mode loopback -u CA3D655ADBDBB49C3912F8F4F7F54014307A2954 --clear-sign --output InRelease Release
}
create_dist_structure
create_packages
generate_release_file
sign_release_file
commit
