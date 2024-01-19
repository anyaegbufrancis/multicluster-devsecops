
# CERTSECRET=keycloak-cert
for i in $(oc get secret  -n openshift-ingress | grep ingress | awk '{print $1}'); oc extract secret/$i -n openshift-ingress
oc create secret tls $CERTSECRET --cert tls.crt --key tls.key -n rhbk-sso
rm -rf tls.*

openssl req -subj '/CN=keycloak.apps.dd-aro.eastus.aroapp.io/O=Demo Keycloak./C=US' -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 365 -out certificate.pem
kubectl create secret tls keycloak-tls-cert --cert certificate.pem --key key.pem -n rhbk-keycloak
rm -rf certificate.pem key.pem

## Replacing ingress & Proxy certs
## Generate CSR for Domain ##
DOMAIN=apps.dd-aro.aroapp.io
openssl req -new -sha256 -nodes -out certserverrequest.csr -newkey rsa:2048 -keyout certserverkey.key -config <(
cat <<-EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext
[ dn ]
C=CA
ST=ON
L=Local
O=RH
OU=OpenShift Cluster
CN=*.$DOMAIN

[ req_ext ]
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.$DOMAIN
EOF
)

## Convert cert to .pem Format (e.g.pkcs to pem) ##
openssl x509 -inform DER -outform DER -text -in <issuedcert.crt> -out <issuedcert.pem>
cat <issuedcert.pem> <intermediatecert.pem> <rootcert.pem> > ocpcert.pem

## Update cluster proxy cert

oc create configmap custom-ca --from-file=ca-bundle.crt=<ocpcert.pem> -n openshift-confip

oc patch proxy/cluster --type=merge --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'

## Update ingress controller Cert

oc create secret tls <Secret Name> --cert=<ocpcert.pem> --key=<certserverkey.key> \
   -n openshift-ingress

oc patch ingresscontroller.operator default --type=merge -p \
    '{"spec":{"defaultCertificate": {"name": "<Secret Name>"}}}' \
    -n openshift-ingress-operator


# oc get cm trusted-ca-bundle -n openshift-config-managed -o yaml