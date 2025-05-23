# Release Process

## Requirements

* GPG Key: You'll need the Hootenanny packaging release public and private
  keys stored in `$HOME/.gnupg-hoot`.  The release key details are:
  * **Key ID**: 7036657A6767A174
  * **Name/E-Mail**: `Hootenanny Packaging <hoot-packaging@digitalglobe.com>`
* `rpmbuild-repo` container
  * Create with `MAVEN_CACHE=0 make rpmbuild-repo`
* AWS credentials with write privileges to the `s3://hoot-repo/el7/release`
  bucket and prefix.

## Hootenanny

1. Set the [`HOOT_VERSION_GEN`](./config.md#hoot_version_gen) environment
   variable with the version number of the desired release:

   ```
   export HOOT_VERSION_GEN=<Hootenanny Version Number>
   ```

   Note: The Hootenanny version tag for the version (e.g., `v0.2.41`
   for a `HOOT_VERSION_GEN=0.2.41`) *must* already exist.

1. Copy m2-cache from S3

   ```
   cd cache/m2/
   aws s3 cp s3://hoot-maven/m2-cache.tar.gz .
   tar -xvf m2-cache.tar
   rm m2-cache.tar
   ```

1. Next, the release archive must be created.  Specify the
   git tag using the [`GIT_COMMIT`](./config.md#git_commit)
   environment variable and run:

   ```
   GIT_COMMIT=v$HOOT_VERSION_GEN MAVEN_CACHE=0 make archive
   ```

   Because `GIT_COMMIT` refers to a git *tag*, don't forget to
   prefix with the version with `v`.  This should generate
   the source archive at `SOURCES/hootenanny-v$HOOT_VERSION_GEN.tar.gz`.

1. The release RPM may now be created from the archive with:

   ```
   make rpm
   ```

   This should generate the following files in `RPMS`:

   * `noarch/hootenanny-autostart-$HOOT_VERSION_GEN-1.el7.noarch.rpm`
   * `noarch/hootenanny-core-deps-$HOOT_VERSION_GEN-1.el7.noarch.rpm`
   * `noarch/hootenanny-core-devel-deps-$HOOT_VERSION_GEN-1.el7.noarch.rpm`
   * `noarch/hootenanny-services-devel-deps-$HOOT_VERSION_GEN-1.el7.noarch.rpm`
   * `x86_64/hootenanny-core-$HOOT_VERSION_GEN-1.el7.x86_64.rpm`
   * `x86_64/hootenanny-services-ui-$HOOT_VERSION_GEN-1.el7.x86_64.rpm`

   Note: The default release value in the RPM version is `1`.
   If a packaging defect requires a subsequent release, it may be
   set with the [`HOOT_RELEASE`](./config.md#hoot_release) environment
   variable.

1. Create a directory for the release repository, and copy the built
   RPMs into it:

   ```
   mkdir -p el7/release
   cp -pv RPMS/{noarch,x86_64}/hootenanny-*$HOOT_VERSION_GEN-1*.rpm el7/release
   ```

1. Start the `rpmbuild-repo` container, specifying the AWS credentials
   in the environment and passing in the proper bind mount locations for
   the GPG keys, the `el7` and the [`scripts`](../scripts) directories:

   ```
   docker run \
     -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
     -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
     -e "AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN" \
     -e "AWS_SECURITY_TOKEN=$AWS_SECURITY_TOKEN" \
     -e "HOOT_VERSION_GEN=$HOOT_VERSION_GEN" \
     -v $HOME/.gnupg-hoot:/rpmbuild/.gnupg:rw \
     -v $(pwd)/el7:/rpmbuild/el7:rw \
     -v $(pwd)/scripts:/rpmbuild/scripts:ro \
     -it --rm hootenanny/rpmbuild-repo
   ```

1. Sign the release packages using `rpmsign`; enter the GPG passphrase
   when prompted:

   ```
   rpmsign --addsign el7/release/hootenanny-*$HOOT_VERSION_GEN-1*.rpm
   ```

1. Copy the existing release repository to `el7/release` using the
   AWS CLI:

   ```
   aws s3 sync s3://hoot-repo/el7/release/ el7/release/
   ```

1. Update the Yum repository with the latest release RPMs:

   ```
   ./scripts/repo-update.sh el7/release
   ```

1. Once the repository is updated, its metadata needs to be
   signed as well.  Provide the passphrase and allow the existing
   `el7/release/repomd.xml.asc` file to be overwritten:

   ```
   ./scripts/repo-sign.sh el7/release
   ```

1. The final step is to reupload the repository back up to S3 using
   the AWS CLI and deleting any old metadata files out of the bucket:

   ```
   aws s3 sync el7/release/ s3://hoot-repo/el7/release/ --delete
   ```

## Dependencies

There are a multitude of Hootenanny dependencies; these instructions
will use an example of upgrading to Tomcat 8.5.34.  Other dependencies
have *multiple* RPMs -- you'll need to modify the instructions accordingly
(e.g., `libgeotiff` will have an architecture of `x86_64` and produce a
`libgeotiff-devel` RPM as well).

1. The configuration file, [config.yml](../config.yml), should be
   updated to the desired version and release iteration (default
   to `1`, unless making a corrective release):

   ```yaml
   versions:
     tomcat8: &tomcat8_version: '8.5.34-1'
   ```

   Note: please have the appropriate source archive from the `.spec`
   file present in `SOURCES` and [verify it's authenticty](./verify.md)
   (if applicable).  Ideally the `config.yml` change and source archive
   would be added in a pull request.

1. Next, build the dependency RPM using `make`:

   ```
   make tomcat8
   ```

   This should produce an RPM at `RPMS/noarch/tomcat8-8.5.34-1.el7.noarch.rpm`.
   It is placed in `noarch` because Java bytecode has no architecture,
   however, compiled C/C++ programs would be placed in `RPMS/x86_64` instead.

1. Create a directory for the release dependency repository, and copy the
   RPMs into it; by default we call it `stable`:

   ```
   mkdir -p el7/deps/stable
   cp -pv RPMS/noarch/tomcat8-8.5.34-1.el7.noarch.rpm el7/deps/stable
   ```

1. Start the `rpmbuild-repo` container, specifying the AWS credentials
   in the environment and passing in the proper bind mount locations for
   the GPG keys, the `el7` and the [`scripts`](../scripts) directories:

   ```
   docker run \
     -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
     -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
     -v $HOME/.gnupg-hoot:/rpmbuild/.gnupg:rw \
     -v $(pwd)/el7:/rpmbuild/el7:rw \
     -v $(pwd)/scripts:/rpmbuild/scripts:ro \
     -it --rm hootenanny/rpmbuild-repo
   ```

1. Sign the release dependency package using `rpmsign`; enter the
   GPG passphrase when prompted:

   ```
   rpmsign --addsign el7/deps/stable/tomcat8-8.5.34-1.el7.noarch.rpm
   ```

1. Copy the existing dependency release repository to `el7/deps/stable`
   using the AWS CLI:

   ```
   aws s3 sync s3://hoot-repo/el7/deps/stable/ el7/deps/stable/
   ```

1. Update the dependency Yum repository with the latest release RPMs:

   ```
   ./scripts/repo-update.sh el7/deps/stable
   ```

1. Once the repository is updated, its metadata needs to be
   signed as well.  Provide the passphrase and allow the existing
   `el7/deps/stable/repomd.xml.asc` file to be overwritten:

   ```
   ./scripts/repo-sign.sh el7/deps/stable
   ```

1. The final step is to reupload the dependency repository back up to S3 using
   the AWS CLI and deleting any old metadata files out of the bucket:

   ```
   aws s3 sync el7/deps/stable/ s3://hoot-repo/el7/deps/stable/ --delete
   ```
