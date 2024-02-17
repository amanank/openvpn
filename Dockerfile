FROM kylemanna/openvpn

RUN apk --no-cache upgrade && apk --no-cache add samba samba-common-tools supervisor nbtscan


