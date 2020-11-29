FROM alpine:edge
RUN \
    apk update ;\
    apk upgrade ;\
    apk add --no-cache \
        curl \
        gcc \
        make \
        musl-dev \
        openssl \
        openssl-dev \
        perl \
        perl-app-cpanminus \
        perl-dev \
        zlib \
        zlib-dev ;\
    cpanm -in --no-man-pages --curl --no-wget --no-lwp \
        CGI::Deurl::XS \
        Class::XSAccessor \
        Cpanel::JSON::XS \
        Dancer2 \
        Dancer2::Serializer::JSON \
        Dancer2::Session::Simple \
        File::stat \
        File::Temp \
        HTML::Entities \
        HTTP::Cookies \
        HTTP::XSCookies \
        HTTP::XSHeaders \
        LWP::Protocol::https \
        LWP::UserAgent \
        Math::Random::ISAAC::XS \
        Mo \
        Mo::default \
        Mo::xs \
        Type::Tiny::XS \
        URL::Encode::XS ;\
    apk del \
        curl \
        gcc \
        make \
        musl-dev \
        openssl-dev \
        perl-app-cpanminus \
        perl-dev \
        zlib-dev ;\
    apk cache clean || : ;\
    mkdir /malicek
ENV TZ=Europe/Prague
EXPOSE 3000
ENTRYPOINT ["perl", "/malicek/malicek.pl"]
