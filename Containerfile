FROM alpine:edge
RUN \
    apk update ;\
    apk upgrade ;\
    apk add \
        curl \
        gcc \
        make \
        musl-dev \
        openssl \
        openssl-dev \
        perl \
        perl-dev \
        perl-app-cpanminus \
        zlib \
        zlib-dev ;\
    cpanm -in --no-man-pages --curl --no-wget --no-lwp \
        Archive::Tar \
        Dancer2 \
        Dancer2::Serializer::JSON \
        Dancer2::Session::Simple \
        File::stat \
        File::Temp \
        HTML::Entities \
        HTTP::Cookies \
        LWP::UserAgent \
        LWP::Protocol::https ;\
    apk del \
        curl \
        gcc \
        make \
        musl-dev \
        openssl-dev \
        perl-dev \
        perl-app-cpanminus \
        zlib-dev ;\
    mkdir /malicek
ENV TZ=Europe/Prague
EXPOSE 3000
ENTRYPOINT ["perl", "/malicek/malicek.pl"]
