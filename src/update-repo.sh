#!/bin/bash

# DEPENDENCY: xsltproc (easy to install; alternatively modify to use another XSLT processor)

BASE_DIR=/update-repo
BIN_DIR=${BASE_DIR}/bin
ETC_DIR=${BASE_DIR}/etc
VAR_DIR=${BASE_DIR}/var

set -e

cd ${VAR_DIR}

if [ ! -f ${ETC_DIR}/REPOSITORIES ]; then
    echo "Please add the URL to at least one repository to the file 'REPOSITORIES' (one repository on each line)'"
    exit
fi

if [ ! -f ${ETC_DIR}/ARTIFACTS ]; then
    echo "Please add coordinates to at least one artifact (groupId:artifactId) to the file 'ARTIFACTS' (one artifact on each line)'"
    exit
fi

if ! which saxonb-xquery >/dev/null; then
    echo "saxonb-xquery is required; please install libsaxonb-java"
    exit 1
fi

if ! which mvn >/dev/null; then
    echo "mvn is required; please install mvn"
    exit 1
fi

if ! which reprepro >/dev/null; then
    echo "reprepro is required; please install reprepro"
    exit 1
fi

function maven-get {
    # $1 = https://oss.sonatype.org/content/repositories/snapshots
    # $2 = org.daisy.pipeline:assembly
    # $3 = 1.8.1-SNAPSHOT
    local repository=$1
    local artifact=$2
    local version=$3
    local dest=$4
    mvn org.apache.maven.plugins:maven-dependency-plugin:2.8:get -DrepoUrl=$repository -Dartifact=$artifact:$version:deb:all -Ddest=$dest -Dtransitive=false
}

function maven-metadata {
    # $1 = https://oss.sonatype.org/content/repositories/snapshots
    # $2 = org.daisy.pipeline:assembly
    local repository=$1
    local artifact=$2
    local version=$3
    wget -O - $1/`echo $2  | sed 's/[\.:]/\//g'`/maven-metadata.xml 2>/dev/null
}

function xquery {
    local query=$1
    saxonb-xquery -qs:"declare option saxon:output 'omit-xml-declaration=yes'; $query" -s:-
}

function versions {
    xquery "string-join(/metadata/versioning/versions/version/text(),'&#xa;')"
}

function lastUpdated {
    xquery "/metadata/versioning/lastUpdated/text()"
}

function is-uptodate {
    artifact=$1
    lastUpdated=$2
    [ -f ${VAR_DIR}/LASTUPDATED ] && cat ${VAR_DIR}/LASTUPDATED | grep -Fxq "$artifact	$lastUpdated"
}

function set-uptodate {
    artifact=$1
    lastUpdated=$2
    if [ -f ${VAR_DIR}/LASTUPDATED ]; then
        cat ${VAR_DIR}/LASTUPDATED | grep -vwF $artifact > ${VAR_DIR}/LASTUPDATED.tmp
        mv ${VAR_DIR}/LASTUPDATED.tmp ${VAR_DIR}/LASTUPDATED
    fi
    echo "$artifact	$lastUpdated" >> ${VAR_DIR}/LASTUPDATED
}

function is-published {
    artifact=$1
    version=$2
    [ -f ${VAR_DIR}/PUBLISHED ] && cat ${VAR_DIR}/PUBLISHED | grep -Fxq $artifact:$version
}

function set-published {
    artifact=$1
    version=$2
    echo "$artifact:$version" >> ${VAR_DIR}/PUBLISHED
}

function reprepro-add {
    local file=$1
    reprepro -b /var/packages/debian -S contrib -P optional includedeb testing /tmp/temp.deb
}

cat ${ETC_DIR}/REPOSITORIES | while read repository; do
    [ "$repository" = "" ] && continue
    echo "Repository: $repository"
    cat ${ETC_DIR}/ARTIFACTS | while read artifact; do
        [ "$artifact" = "" ] && continue
        echo "Artifact: $artifact"
        rm -f /tmp/maven-metadata.xml
        maven-metadata $repository $artifact > /tmp/maven-metadata.xml
        if [ ! -f /tmp/maven-metadata.xml ]; then
            echo "ERROR: $artifact not found in $repository"
            continue
        fi
        lastUpdated=$( cat /tmp/maven-metadata.xml | lastUpdated )
        if is-uptodate $artifact $lastUpdated; then
            echo "Already published latest version, skipping: $artifact"
            continue
        fi
        versions=$( cat /tmp/maven-metadata.xml | versions )
        echo "$versions" | while read -r version; do
            echo "Version: $version"
            if [[ $version == *-SNAPSHOT ]]; then
                echo "Getting $artifact:$version"
                rm -f /tmp/temp.deb
                if maven-get $repository $artifact $version /tmp/temp.deb; then
                    version=$( dpkg-deb -f /tmp/temp.deb Version )
                    if is-published $artifact $version; then
                        echo "Already published, skipping: $artifact:$version"
                    elif reprepro-add /tmp/temp.dev; then
                        set-published $artifact $version
                    fi
                else
                    echo "ERROR: $artifact:$version could not be downloaded"
                fi
            else
                if is-published $artifact $version; then
                    echo "Already published, skipping: $artifact:$version"
                    continue
                fi
                echo "Getting $artifact:$version"
                rm -f /tmp/temp.deb
                if maven-get $repository $artifact $version /tmp/temp.deb; then
                    if reprepro-add /tmp/temp.dev; then
                        set-published $artifact $version
                    fi
                else
                    echo "ERROR: $artifact:$version could not be downloaded"
                fi
            fi
        done
        set-uptodate $artifact $lastUpdated
    done
done
