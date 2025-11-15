#cloud-config
package_upgrade: true
packages:
    - curl
    - unzip
    - jq
    - ca-certificates
    - nodejs
    - npm

write_files:
  - path: /opt/deploy-app.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      exec > /var/log/deploy-app.log 2>&1
      
      echo "Starting deployment"

      ACCESS_TOKEN=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" | jq -r '.access_token')
      MYSQL_PASSWORD=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "https://${kv_name}.vault.azure.net/secrets/${kv_secret_name}?api-version=7.4" | jq -r '.value')
      echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" > /etc/webapp.env
      
      STORAGE_ACCOUNT="${storage_account_name}"
      
      sleep 30
      
      TOKEN=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" | jq -r '.access_token')
      
      curl -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2021-08-06" -o /tmp/web-app.zip "https://$STORAGE_ACCOUNT.blob.core.windows.net/artifacts/web-app.zip"
      
      unzip -q /tmp/web-app.zip -d /opt/web-app
      
      cd /opt/web-app
      npm install
      npm run build
      
      echo "Deployment complete"

  - path: /etc/systemd/system/webapp.service
    content: |
      [Unit]
      Description=NestJS Web Application
      After=network.target
      
      [Service]
      Type=simple
      User=root
      WorkingDirectory=/opt/web-app
      Environment="NODE_ENV=production"
      Environment="PORT=80"
      Environment="MYSQL_HOST=${mysql_host}"
      Environment="MYSQL_PORT=3306"
      Environment="MYSQL_USER=${mysql_user}"
      EnvironmentFile=/etc/webapp.env
      Environment="MYSQL_DATABASE=${mysql_database}"
      ExecStart=/usr/bin/node dist/main
      Restart=always
      RestartSec=10
      StandardOutput=journal
      StandardError=journal
      
      [Install]
      WantedBy=multi-user.target

runcmd:
  - /opt/deploy-app.sh
  
  - systemctl daemon-reload
  - systemctl enable webapp
  - systemctl start webapp
  
  - sleep 5
  - systemctl status webapp
