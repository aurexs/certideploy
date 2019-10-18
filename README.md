# certideploy
Expone certificados generados por acme.sh y consume e instala estos certificados de forma remota


### Instalación con nginx
```
sudo su
wget -O /root/certiimporter.sh https://raw.githubusercontent.com/aurexs/certideploy/master/certiimporter.sh
chmod +0700 /root/certiimporter.sh
rm -rf /etc/nginx/ssl/uan.mx
mkdir -p /etc/nginx/ssl/uan.mx
touch /etc/nginx/ssl/uan.mx/uan.mx.key
/root/certiimporter.sh -d uan.mx -a https://__URL__/certs -u __AUTH:PASS__ -o /etc/nginx/ssl
chmod -R 0700 /etc/nginx/ssl/uan.mx
cat <<EOF | tee /etc/nginx/ssl/uan.mx/uan.mx.key
-----BEGIN RSA PRIVATE KEY-----
bgZvnAYPwgrah2l...6KTm2EH0NXe==
-----END RSA PRIVATE KEY-----
EOF
nginx -t && nginx -s reload
```

### Instalación de crontab
```
crontab -l | { cat; echo '19 01 */6 * * /root/certiimporter.sh -d uan.mx -a https://__URL__/certs -u __AUTH:PASS__ -o /etc/nginx/ssl -r "nginx -t && nginx -s reload" >> /root/certiimporter.log'; } | crontab -
```