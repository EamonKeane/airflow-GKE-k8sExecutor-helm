FROM google/cloud-sdk:216.0.0-alpine

RUN apk --update add openjdk8-jre

RUN gcloud components install \
                      kubectl \
                      gsutil \
                      beta

ENV HELM_LATEST_VERSION="v2.10.0"

RUN apk add --update ca-certificates \
&& apk add --update -t deps wget \
&& apk add jq \
&& wget http://storage.googleapis.com/kubernetes-helm/helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz \
&& tar -xvf helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz \
&& mv linux-amd64/helm /usr/local/bin \
&& apk del --purge deps \
&& rm /var/cache/apk/* \
&& rm -f /helm-${HELM_LATEST_VERSION}-linux-amd64.tar.gz

ENTRYPOINT [“helm”]