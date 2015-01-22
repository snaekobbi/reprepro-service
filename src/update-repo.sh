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

if [ "`which xsltproc | grep -v \"not found\" | wc -l`" = "0" ]; then
    echo "xsltproc is required; please install xsltproc"
    exit
fi

if [ "`which mvn | grep -v \"not found\" | wc -l`" = "0" ]; then
    echo "mvn is required; please install mvn"
    exit
fi

function get {
    # $1 = https://oss.sonatype.org/content/repositories/snapshots
    # $2 = org.daisy.pipeline:assembly
    # $3 = 1.8.1-SNAPSHOT
    mvn org.apache.maven.plugins:maven-dependency-plugin:2.8:get -DrepoUrl=$1 -Dartifact=$2:$3:deb:all -Ddest=/tmp/temp.deb -Dtransitive=false
}
 
function versions {
    # $1 = https://oss.sonatype.org/content/repositories/snapshots
    # $2 = org.daisy.pipeline:assembly
    wget -O - $1/`echo $2  | sed 's/[\.:]/\//g'`/maven-metadata.xml 2> /dev/null | xsltproc ${BIN_DIR}/maven-metadata-to-versions.xsl -
}

cat ${ETC_DIR}/REPOSITORIES | while read repository; do
    if [ "$repository" = "" ]; then continue; fi
    echo "Repository: $repository"
    cat ${ETC_DIR}/ARTIFACTS | while read artifact; do
        if [ "$artifact" = "" ]; then continue; fi
        echo "Artifact: $artifact"
        versions $repository $artifact | while read -r version; do
            if [ "$version" = "" ]; then continue; fi
            if [ ! -f ${VAR_DIR}/PUBLISHED ] || [ "`cat ${VAR_DIR}/PUBLISHED | grep $artifact:$version | wc -l`" = "0" ] ; then
                echo "getting $artifact:$version"
                get $repository $artifact $version
                if [ -f /tmp/temp.deb ]; then
                    if [ "`which reprepro | grep -v \"not found\" | wc -l`" -gt "0" ]; then # skip if reprepro not installed (for testing)
                        if reprepro -b /var/packages/debian -S contrib -P optional includedeb testing /tmp/temp.deb ; then
                            echo "$artifact:$version" >> ${VAR_DIR}/PUBLISHED
                        fi
                    fi
                    rm /tmp/temp.deb
                else
                    echo "$artifact:$version does not contain a deb; marking as PUBLISHED to avoid future checks"
                    echo "$artifact:$version" >> ${VAR_DIR}/PUBLISHED
                fi
            else
                echo "already published, skipping: $artifact:$version"
            fi
        done
    done
done
