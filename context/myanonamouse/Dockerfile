FROM alpine:latest

RUN apk add --no-cache curl bash tzdata bind-tools

LABEL build_version="Myanonamouse-Updater, Version: 1.0.0"
LABEL maintainer=patrick-sluth

COPY myanonamouse-seedbox-update /opt/

RUN chmod +x /opt/myanonamouse-seedbox-update

CMD /opt/myanonamouse-seedbox-update