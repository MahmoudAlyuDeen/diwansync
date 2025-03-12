# Introduction

A private personal server hosting photos and files.

Running on cheap, refurbished, low powered, and portable machines at home.

Securely accessible everywhere, completely free.

- [File sharing demo](https://storage.alyudeen.mywire.org/share/P51zqRA8K_PZxDp-yKDLHw)
- [Photo sharing demo](https://immich.mahmoud.alyudeen.mywire.org/share/lbG8F_Ag2aipTvQkJQpvoLSe6KIqyTp0sCX8Gey5nhlDSHmHZTwqUhDmWT2qSZP8QfI)

# This Repository Structure

### Proxmox machine configuration
### utils
### docker compose files
### Secrets and environment variables

# System details

## Main node

### Operating System

Proxmox VE - https://www.proxmox.com/en/

Runs services in isolation in separate virtual machines or lightweight linux containers with a GUI and easy backup / restore.

### Recommended terminal utilities

- [lazygit](https://github.com/jesseduffield/lazygit): GUI git client.
  - https://github.com/jesseduffield/lazygit?tab=readme-ov-file#ubuntu
- [Midnight Commander](https://github.com/MidnightCommander/mc): File manager.
  - https://askubuntu.com/questions/1071392/how-can-i-install-midnight-commander-on-ubuntu-18-04-1

### Hosted Services

- 201-home
  - Purpose: Control lights and smart devices from web and mobile apps.
  - Project: https://www.home-assistant.io
  - Guide: https://youtu.be/65Lhn90f3YI
- 202-storage
  - Purpose: Access and share files from a web browswer
  - Project: https://github.com/gtsteffaniak/filebrowser
  - Guide: https://youtu.be/W2yZ5_sd9Hc
  - Notes: The config files use filebrowswer quantum, a fork of filebrowser.
- 203-nginx
  - Purpose: Access services using pretty https URLs, with SSL certificate creation and management.
  - Project: https://github.com/NginxProxyManager/nginx-proxy-manager
  - Guide: https://youtu.be/sRI4Xhyedw4
- 204-ddns
  - Purpose: Make the server remotely accessible by updating DDNS providers with realtime IP address.
  - Project: https://github.com/qdm12/ddns-updater
  - Guide: Use the included config files.
  - DDNS explained: https://www.youtube.com/watch?v=rOLGvZagdC0
- 205-sync
  - Purpose: Send files periodically to backup node for disaster recovery.
  - Project: https://github.com/syncthing/syncthing
  - Guide: Use the included config files.
- 206-homebackus
  - Purpose: Enable home assistant backups over the network in files for disaster recovery.
  - Project: https://github.com/dperson/samba
  - Guide: Use the included config files.
  - Notes: A (full) backup automatically restores automations, rules, and device connections.
- 207-auth
  - Purpose: Require 2 factor authentication to access services and enable passwordlesss login.
  - Project: https://github.com/goauthentik/authentik
  - Guide: https://www.youtube.com/playlist?list=PLH73rprBo7vSkDq-hAuXOoXx2es-1ExOP
- 209-logs
  - Purpose: Display access logs by country, ip, destination service, and other parameters.
  - Project: https://github.com/xavier-hernandez/goaccess-for-nginxproxymanager
  - Guide: Use the included config files.
- 22#-immich
  - Purpose: Automatic phone backup with sharing and albums.
  - Project: https://github.com/immich-app/immich
  - Guide: https://immich.app/docs/overview/quick-start

## Backup node

- **Operating system**: Windows.
- **Hosted service**: Syncthing.
  - Purpose: Receive files periodically from main node for disaster recovery.
  - Installer runs automatically on windows boot: https://github.com/Bill-Stewart/SyncthingWindowsSetup
 
# Architecture Diagram

<img src="architecture/diagram.png">

# Hardware

#### Main node

Dell OptiPlex 7050 - refurbished
- Intel i5 6600 3.30GHz + 16gb memory
- 256gb boot + 1tb storage 

#### Backup node

Dell OptiPlex 7050 - refurbished
- Intel i3 7100T 3.40GHz + 8gb memory
- 256gb boot + 1tb storage

<img src="images/optiplex.png">

<img src="images/system.jpeg">

### Screenshots

#### Phone

| First Header  | Second Header |
|--------|--------|
| ![IMG_6221_preview](https://github.com/user-attachments/assets/b7884f62-dd9f-49c6-bc83-071d76787871) | ![IMG_6260_preview](https://github.com/user-attachments/assets/f04821de-63a1-4a38-82ef-5a54558d52f9) |
| ![IMG_6274_preview](https://github.com/user-attachments/assets/8deca6eb-ff9c-4357-8bd2-16e033c3c47a) | ![IMG_7445_preview](https://github.com/user-attachments/assets/c7904d0c-bb2a-4c10-af86-867b2060704c) |

#### Web

<p> <img width="800" alt="image" src="https://github.com/user-attachments/assets/560400c8-5a20-43b8-85ab-2913d978aaf3" /> </p>
<p> <img width="800" alt="image" src="https://github.com/user-attachments/assets/1cb9d0ae-e270-4c09-8b72-1371782958b1" /> </p>
<img width="1296" alt="image" src="https://github.com/user-attachments/assets/2d36e6f0-7df1-4741-bd20-d8c17904bde4" />
<img width="1292" alt="image" src="https://github.com/user-attachments/assets/1ff1719d-95a3-4efe-8b15-a362da428b84" />
<img width="1293" alt="image" src="https://github.com/user-attachments/assets/6697d059-19de-4586-99b8-4a071eb06c64" />
<img width="1294" alt="image" src="https://github.com/user-attachments/assets/033a9bde-4b4f-4d78-87ea-4f4ab686e7f9" />
<img width="1293" alt="Screenshot 2025-03-12 at 9 47 36 AM" src="https://github.com/user-attachments/assets/de0c5bd6-a1ab-42eb-9069-58f141ca15bb" />
<img width="1298" alt="image" src="https://github.com/user-attachments/assets/f4c50c84-7ea6-4d1a-b12d-21027c79d499" />
<img width="1296" alt="image" src="https://github.com/user-attachments/assets/57b82ac5-eb7b-40d6-8640-5fc35eb7b1cb" />
<img width="1294" alt="Screenshot 2025-03-12 at 10 32 26 AM" src="https://github.com/user-attachments/assets/5470a6f7-3a7b-4841-b7f0-4ea503911ccd" />
<p> <img width="800" alt="image" src="https://github.com/user-attachments/assets/c4593dd8-9dd9-4305-b4c8-bec819cd579d" /> </p>
