#!/bin/bash
set -e

source /init.sh

function help () {
# Using a here doc with standard out.
cat <<-END

Usage: docker run [OPTIONS] docker-artifactory.sln.nc/speed/speed-dockerize

Dockerizer l'application du répertoire courant
Le fichier Dockerfile doit être présent à la racine du projet
L'action de dockérizer consiste à prendre des fichiers plats en entrée et générer une image docker en sortie.
Le nom de l'image est déduit de l'url Gitlab remote origin, il y a donc correspondance entre les noms de groupes et de projets entre Gitlab et Artifactory

Options:
  -e ARTIFACTORY_URL=string                         URL d'Artifactory (ex: https://artifactory.sln.nc)
  -e ARTIFACTORY_USER=string                        Username d'accès à Artifactory (ex: prenom.nom)
  -e ARTIFACTORY_PASSWORD=string                    Mot de passe d'accès à Artifactory
  -e PUBLISH=boolean                                Activer la publication de l'image docker sur Artifactory (default: false)
  -e NO_CACHE=boolean                               Désactiver l'utilisation du cache lors du docker build (default: false)  
  --env-file ~/speed.env                            Fichier contenant les variables d'environnement précédentes
  -v \$(pwd):/srv/speed                              Bind mount du répertoire racine de l'application à dockérizer
  -v /var/run/docker.sock:/var/run/docker.sock      Bind mount de la socket docker pour le lancement de commandes docker lors de la dockérization
END
}

while [ -n "$1" ]; do
    case "$1" in
        -h | --help | help)
            help
            exit 0
            ;;
        *)
            echo "Usage:  {h|--help|help} Afficher l'aide pour la configuration de lancement du container"
            exit 1
    esac 
done

printmainstep "Dockerisation de l'application"
printstep "Vérification des paramètres d'entrée"
docker version
init_env

check_docker_env

TAG=${TAG:-"latest"}
IMAGE=$ARTIFACTORY_DOCKER_REGISTRY/$PROJECT_NAMESPACE/$PROJECT_NAME:$TAG
PUBLISH=${PUBLISH:-"false"}
NO_CACHE=${NO_CACHE:-"false"}

echo ""
printinfo "DOCKERFILE : $DOCKERFILE"
printinfo "IMAGE      : $IMAGE"
printinfo "PROXY      : $PROXY"
printinfo "NO_PROXY   : $NO_PROXY"
printinfo "PUBLISH    : $PUBLISH"
printinfo "NO_CACHE   : $NO_CACHE"
printinfo "ARTIFACT   : $ARTIFACT"

if [[ "$NO_CACHE" == "true" ]]; then ARGS="--no-cache"; fi
if [[ "$ARTIFACT" != "" ]]; then ARGS="$ARGS --build-arg ARTIFACT=$ARTIFACT"; fi
if [[ "$TAG" != "" ]]; then ARGS="$ARGS --build-arg TAG=$TAG"; fi

printstep "Création de la nouvelle image Docker"
docker login -u $ARTIFACTORY_USER -p $ARTIFACTORY_PASSWORD $ARTIFACTORY_DOCKER_REGISTRY
OLD_IMAGE_ID=$(docker inspect $IMAGE | jq .[0].Id | tr -d '"')
docker build $ARGS \
             --build-arg http_proxy=$PROXY  \
             --build-arg https_proxy=$PROXY \
             --build-arg no_proxy=$NO_PROXY \
             --build-arg HTTP_PROXY=$PROXY  \
             --build-arg HTTPS_PROXY=$PROXY \
             --build-arg NO_PROXY=$NO_PROXY \
             --build-arg ARTIFACTORY_URL=$ARTIFACTORY_URL \
             --build-arg ARTIFACTORY_USER=$ARTIFACTORY_USER \
             --build-arg ARTIFACTORY_PASSWORD=$ARTIFACTORY_PASSWORD \
       -f $DOCKERFILE -t $IMAGE .
NEW_IMAGE_ID=$(docker inspect $IMAGE | jq .[0].Id | tr -d '"')

if [[ "$PUBLISH" == "true" ]]; then
    printstep "Publication de la nouvelle image Docker dans Artifactory"
    ARTIFACTORY_IMAGE_ID=`curl -u $ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD --silent --noproxy '*' "$ARTIFACTORY_URL/artifactory/docker/$PROJECT_NAMESPACE/$PROJECT_NAME/$TAG/manifest.json" | jq .config.digest | tr -d '"'`
    if [[ "$ARTIFACTORY_IMAGE_ID" != "$NEW_IMAGE_ID" ]]; then
        docker push $IMAGE
    else
       printinfo "Nouvelle image docker identique à la précédente, docker push inutile"
    fi    
fi

if [[ "$OLD_IMAGE_ID" != "$NEW_IMAGE_ID" ]]; then
    printstep "Suppression de l'image Docker précédente du cache local"
    if [[ -n "$OLD_IMAGE_ID" ]]; then docker rmi $OLD_IMAGE_ID || true; fi
fi
