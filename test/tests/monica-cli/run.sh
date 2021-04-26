#!/bin/bash
set -eo pipefail

dir="$(dirname "$(readlink -f "$BASH_SOURCE")")"

image="$1"

mysqlImage='mysql:5.7'
# ensure the mysqlImage is ready and available
if ! docker image inspect "$mysqlImage" &> /dev/null; then
	docker pull "$mysqlImage" > /dev/null
fi

# Create an instance of the container-under-test
mysqlCid="$(docker run -d \
	-e MYSQL_RANDOM_ROOT_PASSWORD=true \
	-e MYSQL_DATABASE=monica \
	-e MYSQL_USER=homestead \
	-e MYSQL_PASSWORD=secret \
	"$mysqlImage")"
trap "docker rm -vf $mysqlCid > /dev/null" EXIT

cid="$(docker run -d \
	--link "$mysqlCid":mysql \
	-e DB_HOST=mysql \
	"$image")"
trap "docker rm -vf $cid $mysqlCid > /dev/null" EXIT

_artisan() {
	docker exec "$cid" php artisan "$@"
}

# returns success when all database migrations are finished
_migrate_done() {
	local status
	status="$(_artisan migrate:status)"
	if grep -q ' Yes ' <<<"$status" && ! grep -q ' No ' <<<"$status"; then
		return 0
	fi
	return 1
}

# check artisan command for specific output; print and error when not found
_artisan_test() {
	local match="$1"; shift
	output="$(_artisan "$@")"
	if ! grep -iq "$match" <<<"$output"; then
		echo "Match: '$match' not found in: $output"
		return 1
	fi
}

# Give some time to install
. "$dir/../../retry.sh" --tries 30 '_migrate_done'

# Check if installation is complete
_artisan monica:getversion > /dev/null
_artisan schedule:run
_artisan_test 'No scheduled commands are ready to run.' schedule:run
