#!/bin/bash
# Copyright (C) 2018 Radiant Solutions (http://www.radiantsolutions.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
set -Eeuo pipefail

# Optional verbose debugging: set DEBUG=1 in the environment to enable xtrace
if [[ "${DEBUG:-0}" == "1" ]]; then
  set -x
fi


# Helpful error trap to show the failing line and command
error_trap() {
  local ec=$?
  echo "[ERROR] Exit $ec at line $LINENO while running: ${BASH_COMMAND}" >&2
  exit "$ec"
}
trap error_trap ERR

die() { echo "[FATAL] $*" >&2; exit 2; }

# Default variables.
HOOT_BRANCH="${HOOT_BRANCH:-master}"
ARCHIVE_BUCKET="${ARCHIVE_BUCKET:-hoot-archives}"
ARCHIVE_PREFIX="${ARCHIVE_PREFIX:-circle/$HOOT_BRANCH}"
REPO_BUCKET="${REPO_BUCKET:-hoot-repo}"
REPO_PREFIX="${REPO_PREFIX:-el7/$HOOT_BRANCH}"

echo "[INFO] HOOT_BRANCH=$HOOT_BRANCH"
echo "[INFO] ARCHIVE_BUCKET=$ARCHIVE_BUCKET"
echo "[INFO] ARCHIVE_PREFIX=$ARCHIVE_PREFIX"
echo "[INFO] REPO_BUCKET=$REPO_BUCKET"
echo "[INFO] REPO_PREFIX=$REPO_PREFIX"

# Determine what the latest master archive is.
LATEST_ARCHIVE="$(./scripts/latest-archive.sh -b "$ARCHIVE_BUCKET" -p "$ARCHIVE_PREFIX")"
if [[ -z "$LATEST_ARCHIVE" ]]; then
  die "LATEST_ARCHIVE is empty. Check credentials and that archives exist under s3://$ARCHIVE_BUCKET/$ARCHIVE_PREFIX"
fi

echo "[INFO] LATEST_ARCHIVE=$LATEST_ARCHIVE"

# Query the master repository for number of RPMs with the
# archive's git hash.
NUM_RPMS="$(./scripts/query-archive.sh -a "$LATEST_ARCHIVE" -b "$REPO_BUCKET" -p "$REPO_PREFIX")" || die "query-archive.sh failed"
if ! [[ "$NUM_RPMS" =~ ^[0-9]+$ ]]; then
  die "NUM_RPMS is not numeric (got: '$NUM_RPMS'). Check repo bucket/prefix and permissions."
fi

echo "[INFO] NUM_RPMS=$NUM_RPMS"

if [ "$NUM_RPMS" = "0" ]; then
    # Retrieve the latest archive.
    aws s3 cp "s3://$ARCHIVE_BUCKET/$LATEST_ARCHIVE" SOURCES/ --quiet
    ls -l SOURCES || true

    # Seed the Maven cache.
    source shell/Vars.sh
    maven_cache

    # Change ownership permissions on directories accessed in container to
    # match that of the rpmbuild user in the public Docker Hub.
    if command -v sudo >/dev/null 2>&1; then
      sudo chown -R 1000:1000 cache el7 RPMS SOURCES || true
    else
      chown -R 1000:1000 cache el7 RPMS SOURCES || true
    fi

    # Build the RPM and copy RPMs into workspace folder.
    ./shell/BuildHoot.sh

    # Move produced RPMs if any; fail with a clear message if none were built
    shopt -s nullglob
    rpms=(RPMS/noarch/*.rpm RPMS/x86_64/*.rpm)
    if (( ${#rpms[@]} > 0 )); then
      # Use sudo if available but do not fail solely on permission issues
      if command -v sudo >/dev/null 2>&1; then
        sudo mv -v "${rpms[@]}" el7 || true
      else
        mv -v "${rpms[@]}" el7
      fi
      echo "[INFO] Moved ${#rpms[@]} RPM(s) to el7/"
    else
      die "Build produced no RPMs under RPMS/noarch or RPMS/x86_64"
    fi
    shopt -u nullglob
else
    touch el7/none.rpm
fi
