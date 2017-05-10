#!/bin/bash
set -e

printmainstep "Dockerisation de l'application"
printstep "Vérification des paramètres d'entrée"
docker version
init_env

check_docker_env

printstep "Création de la nouvelle image Docker"
OLD_IMAGE_ID=$(docker images -q $IMAGE)
docker build $ARGS \
             --build-arg http_proxy=$PROXY  \
             --build-arg https_proxy=$PROXY \
             --build-arg HTTP_PROXY=$PROXY  \
             --build-arg HTTPS_PROXY=$PROXY \
       -f Dockerfile -t $IMAGE .
NEW_IMAGE_ID=$(docker images -q $IMAGE)

if [[ "$OLD_IMAGE_ID" != "$NEW_IMAGE_ID" ]]; then
    printstep "Publication de la nouvelle image Docker dans Artifactory"
    docker login -u $ARTIFACTORY_USER -p $ARTIFACTORY_PASSWORD $ARTIFACTORY_DOCKER_REGISTRY
    docker push $IMAGE
    printstep "Suppression de l'image Docker précédente du cache local"
    if [[ -n "$OLD_IMAGE_ID" ]] && [[ $NB_DEPENDENT_CHILD_IMAGES -ne 0 ]]; then 
        NB_DEPENDENT_CHILD_IMAGES=`docker inspect --format='{{.Id}} {{.Parent}}' $(docker images --filter since=$OLD_IMAGE_ID -q) | wc -l`
        if [[ $NB_DEPENDENT_CHILD_IMAGES -ne 0 ]]; then docker rmi $OLD_IMAGE_ID; fi
    fi
else
   printinfo "Nouvelle image docker identique à la précédente, docker push inutile"
fi
