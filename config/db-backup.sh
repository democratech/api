#!/bin/bash
/usr/bin/mongodump -d democratech -o /home/democratech/backup/
now=$(date +"%Y%m%d-%H:%M")
tar cvfz /home/democratech/archives/$now-db.backup.tgz /home/democratech/backup/
