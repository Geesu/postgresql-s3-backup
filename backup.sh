#!/bin/bash

export S3_ACCESS_KEY_ID=
export S3_SECRET_ACCESS_KEY=
export S3_BUCKET=
export PG_DBNAME=
RBENV_ROOT=/usr/local/rbenv/ /usr/local/rbenv/bin/rbenv exec ruby backup.rb