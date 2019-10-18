# certideploy
Expone certificados generados por acme.sh y consume e instala estos certificados de forma remota

## Nginx

### Instalación en nginx
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

### Instalación de crontab para nginx
```
crontab -l | { cat; echo '19 01 */6 * * /root/certiimporter.sh -d uan.mx -a https://__URL__/certs -u __AUTH:PASS__ -o /etc/nginx/ssl -r "nginx -t && nginx -s reload" >> /root/certiimporter.log'; } | crontab -
```


### Instalación en Proxmox
Proxmox necesita el certificado y la llave en las siguientes rutas:
```
/etc/pve/local/pveproxy-ssl.key
/etc/pve/local/pveproxy-ssl.pem
```
El parámetro --fullchain-file copia el archivo con el certificado y el ca combinados a la ruta que se especifique.
```sh
sudo su
wget -O /root/certiimporter.sh https://raw.githubusercontent.com/aurexs/certideploy/master/certiimporter.sh
chmod +0700 /root/certiimporter.sh
rm -rf /etc/ssl/certs/uan.mx
mkdir -p /etc/ssl/certs/uan.mx
touch /etc/ssl/certs/uan.mx/uan.mx.key
/root/certiimporter.sh -d uan.mx -a https://__URL__/certs -u __AUTH:PASS__ -o /etc/ssl/certs --fullchain-file /etc/pve/local/pveproxy-ssl.pem
chmod -R 0750 /etc/ssl/certs/uan.mx
chmod -R 0640 /etc/ssl/certs/uan.mx
cat <<EOF | tee /etc/ssl/certs/uan.mx/uan.mx.key
-----BEGIN RSA PRIVATE KEY-----
bgZvnAYPwgrah2l...6KTm2EH0NXe==
-----END RSA PRIVATE KEY-----
EOF
cat /etc/ssl/certs/uan.mx/uan.mx.key > /etc/pve/local/pveproxy-ssl.key
```

### Instalación de crontab para Proxmox
```
crontab -l | { cat; echo '19 01 */6 * * /root/certiimporter.sh -d uan.mx -a https://__URL__/certs -u __AUTH:PASS__ -o /etc/ssl/certs --fullchain-file /etc/pve/local/pveproxy-ssl.pem -r "systemctl restart pveproxy" >> /root/certiimporter.log'; } | crontab -```

