#!/bin/bash

# export needed environment vars
export APPDIR=/dfirtrack
export PGPASSWORD=${DB_PASSWORD:-'dfirtrack'}
export PGHOST=${DB_HOST:-'db'}
export PGUSER=${DB_USER:-'dfirtrack'}
export PGNAME=${DB_NAME:-'dfirtrack'}
export DISABLE_HTTPS=${DISABLE_HTTPS:-'true'}

# wait for psql docker container to come up
until psql -h $PGHOST -U $PGUSER -d $PGNAME -c '\q'
do
    echo "Waiting for Postgres..."
    sleep 1
done

# choose the right nginx conf
if [ $DISABLE_HTTPS = 'true' ]
  then ln -s /etc/nginx/sites-available/dfirtrack_insecure /etc/nginx/sites-enabled/
  else ln -s /etc/nginx/sites-available/dfirtrack /etc/nginx/sites-enabled/
fi

# we copy the files that were modified during the docker build process to the "dynamic" directory
cp /dfirtrack-static/dfirtrack/local_settings.py /dfirtrack/dfirtrack/local_settings.py
cp /dfirtrack-static/dfirtrack/settings.py /dfirtrack/dfirtrack/settings.py
cp -r /dfirtrack-static/markdown/ /dfirtrack/markdown/

service nginx start
# we have to collectstatic here (and not during docker build), since we want to do it from the dynamic dfirtrack dir
$APPDIR/manage.py collectstatic --noinput
$APPDIR/manage.py migrate
$APPDIR/manage.py createcachetable
$APPDIR/manage.py qcluster &

if [ $DJANGO_SUPERUSER_USERNAME ] && [ $DJANGO_SUPERUSER_EMAIL ] && [ $DJANGO_SUPERUSER_PASSWORD ]; then
    echo "[+] Creating super user $DJANGO_SUPERUSER_USERNAME"
    $APPDIR/manage.py createsuperuser --noinput
fi

# need to cd to /dfirtrack since it's dynamic and cannot be the container's workdir
cd $APPDIR
# the --reload flag allows for automatic gunicorn reloads on file changes
gunicorn --reload --log-file=/var/log/gunicorn.log --workers 4 --bind localhost:5000 dfirtrack.wsgi &
sleep 10
echo "Container started"
echo "!!!! You may run docker/dev/setup_admin.sh from the host system to create a new superuser !!!!"
sleep infinity
