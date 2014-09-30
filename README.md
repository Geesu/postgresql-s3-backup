postgresql-backup
=================

Project for backing up our postgresql DB to S3.  It should be run on the production database server.

Store amazon access credentials in your local environment:
S3_ACCESS_KEY_ID
S3_SECRET_ACCESS_KEY
S3_BUCKET
PG_USERNAME
PG_DBNAME

#### Credits

Guide followed: http://www.wekeroad.com/2011/10/02/how-to-backup-your-postgres-db-to-amazon-nightly/

Combined with: http://blog.vicecity.co.uk/post/4425574978/multipart-uploads-fog-threads-win
