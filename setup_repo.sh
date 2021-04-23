#!/bin/bash


# Perform a simple recursice finad-and-replace on all variables defined in setup.cov
export SETUP_CONF_PATH=setup.conf # location of the setup config
export DISTRIBUTION_PATH=./distribution # folder where the distributions YAML files are to be found

while IFS="=" read PLACEHOLDER VALUE # While look that will perform simple parsing. On each line MY_VAR=123 will be read into PLACEHOLDER=MY_VAR, VALUE=123
do
  # recursively look for $PLACEHOLDER in all files in the $DISTRIBUTION_PATH and replace it with $VALUE
  VALUE=$(echo "${VALUE////$'\/'}") #escape forward slashes (need for sed to work correctly)
  grep -rli ${PLACEHOLDER} ${DISTRIBUTION_PATH}/* | xargs -i@ sed -i "s/${PLACEHOLDER}/${VALUE}/g" @ #perform recursive replace
done <${SETUP_CONF_PATH} # pass the setup config into the while look


# set secretkey for metallb
echo "generating secret for metallb"
yq eval -i ".stringData.secretkey = \"$(openssl rand -base64 128)\"" metallb/secret.yaml



if [ -z "$1" ]
    then
        echo "no repo URL provided, using upstream"
    else
        yq e -i ".spec.source.repoURL = \"$1\"" kubeflow.yaml
        for filename in ${DISTRIBUTION_PATH}/argocd-applications/*.yaml; do
            if [ $(yq e ".spec.source | has (\"helm\")" $filename) == false ]
                then
                    yq e -i ".spec.source.repoURL = \"$1\"" $filename
            fi
        done
fi

if [ -z "$2" ]
    then
        echo "no target branch provided, using HEAD"
    else
        yq e -i ".spec.source.targetRevision = \"$2\"" kubeflow.yaml
        for filename in ${DISTRIBUTION_PATH}/argocd-applications/*.yaml; do
            if [ $(yq e ".spec.source | has (\"helm\")" $filename) == false ]
                then
                    yq e -i ".spec.source.targetRevision = \"$2\"" $filename
            fi
        done
fi

